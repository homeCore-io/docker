#!/bin/sh
# homeCore appliance entrypoint.
#
# Single-base-dir layout: everything under $HOMECORE_HOME (default
# /homecore). The operator bind-mounts that one directory; the
# entrypoint seeds it on first boot (config files + ui symlink) and
# launches hc-core + each enabled plugin.
#
# - hc-core reads $HOMECORE_HOME from env, so all path-relative fields
#   in config (storage, rules, dist_path, jwt_secret_file,
#   initial_admin_password_file) resolve under one tree.
# - First boot copies defaults into $HOMECORE_HOME/config/. Subsequent
#   boots preserve operator edits.
# - Plugin subset comes from $HC_PLUGINS (default: all bundled).
#
# tini handles PID-1 signal forwarding + zombie reaping for the
# background plugins.

set -e

HOME_DIR="${HOMECORE_HOME:-/homecore}"
DEFAULTS_DIR=/opt/homecore/defaults
UI_SRC=/opt/homecore/ui

CONFIG_DIR="$HOME_DIR/config"
DATA_DIR="$HOME_DIR/data"
RULES_DIR="$HOME_DIR/rules"
CORE_CONFIG="$CONFIG_DIR/homecore.toml"

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

# ─── Seed plugin configs (only for the enabled subset) ──────────────
for p in $HC_PLUGINS; do
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
# match the env-supplied HOMECORE_HOME. Belt-and-suspenders: hc-core
# would honor either alone, but specifying both makes the intent
# obvious in `ps` output and the run logs.
echo "[appliance] starting hc-core with home=$HOME_DIR"
/usr/local/bin/homecore --home "$HOME_DIR" --config "$CORE_CONFIG" &
CORE_PID=$!

# Embedded broker takes a moment to bind. Plugins that connect too
# eagerly will retry, but this avoids a noisy first-second of logs.
sleep 3

# ─── Start each enabled plugin ──────────────────────────────────────
for p in $HC_PLUGINS; do
    bin="/usr/local/bin/$p"
    config="$CONFIG_DIR/$p/config.toml"

    if [ ! -x "$bin" ]; then
        echo "[appliance] skipping $p (binary $bin not found)" >&2
        continue
    fi
    if [ ! -f "$config" ]; then
        echo "[appliance] skipping $p (config $config not found)" >&2
        continue
    fi

    echo "[appliance] starting $p"
    "$bin" "$config" &
done

# Wait on hc-core. If hc-core dies the container dies; plugins are
# orphans → tini reaps them. Tradeoff: a plugin crash doesn't take
# down the container (intentional — appliance is for evaluation, not
# strict failure semantics).
wait "$CORE_PID"
