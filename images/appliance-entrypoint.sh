#!/bin/sh
# homeCore appliance entrypoint.
#
# Single-base-dir layout: everything under $HOMECORE_HOME (default
# /homecore). The operator bind-mounts that one directory; the
# entrypoint seeds it on first boot (config files + ui symlink) and
# launches hc-core. hc-core itself supervises each enabled plugin
# as a managed child process — see [[plugins]] in the seeded
# config/homecore.toml. Plugins all start disabled; the operator
# flips `enabled = true` on the ones their hardware needs.

set -e

HOME_DIR="${HOMECORE_HOME:-/homecore}"
DEFAULTS_DIR=/opt/homecore/defaults
UI_SRC=/opt/homecore/ui

CONFIG_DIR="$HOME_DIR/config"
DATA_DIR="$HOME_DIR/data"
RULES_DIR="$HOME_DIR/rules"
CORE_CONFIG="$CONFIG_DIR/homecore.toml"

# Plugins whose default configs we seed on first boot. The set matches
# the [[plugins]] declarations in homecore.appliance.toml — every
# bundled binary gets a working config so flipping `enabled = true`
# is the only thing the operator needs to do.
BUNDLED_PLUGINS="hc-hue hc-wled hc-yolink hc-lutron hc-sonos \
                 hc-isy hc-zwave hc-caseta hc-thermostat hc-ecowitt"

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$RULES_DIR"

# ─── Seed core config ───────────────────────────────────────────────
if [ ! -f "$CORE_CONFIG" ]; then
    cp "$DEFAULTS_DIR/homecore.toml" "$CORE_CONFIG"
    echo "[appliance] seeded core config at $CORE_CONFIG"
fi

# ─── UI symlink ─────────────────────────────────────────────────────
# Baked WASM bundle lives at /opt/homecore/ui (outside the volume).
# Symlink so the seeded config's relative `dist_path = "ui"` resolves.
# Idempotent: -f replaces any prior symlink without complaint.
if [ -d "$UI_SRC" ]; then
    ln -sfn "$UI_SRC" "$HOME_DIR/ui"
fi

# ─── Seed per-plugin configs (regardless of enabled state) ──────────
# Files exist before the operator flips enabled=true so plugins have
# working defaults the moment they're enabled.
for p in $BUNDLED_PLUGINS; do
    plugin_default="$DEFAULTS_DIR/$p/config.toml"
    plugin_config_dir="$CONFIG_DIR/$p"
    plugin_config="$plugin_config_dir/config.toml"

    if [ ! -f "$plugin_default" ]; then
        echo "[appliance] WARN: $p has no bundled default ($plugin_default missing)" >&2
        continue
    fi

    if [ ! -f "$plugin_config" ]; then
        mkdir -p "$plugin_config_dir"
        cp "$plugin_default" "$plugin_config"
        echo "[appliance] seeded $p config at $plugin_config"
    fi
done

# ─── Start hc-core ──────────────────────────────────────────────────
# --home + --config flags make hc-core's path resolution explicit and
# match the env-supplied HOMECORE_HOME. hc-core supervises each
# [[plugins]] entry whose enabled = true; tini reaps them on shutdown.
echo "[appliance] starting hc-core with home=$HOME_DIR"
exec /usr/local/bin/homecore --home "$HOME_DIR" --config "$CORE_CONFIG"
