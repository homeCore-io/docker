#!/bin/sh
# homeCore appliance entrypoint.
#
# Single-base-dir layout: everything under $HOMECORE_HOME (default
# /homecore). The operator bind-mounts that one directory; the
# entrypoint seeds it on first boot (config files + ui symlink) and
# launches hc-core. hc-core itself supervises each enabled plugin
# as a managed child process — see [[plugins]] in the seeded
# config/homecore.toml.
#
# UID/GID handling: the container starts as root, looks at the
# bind-mount's owner, and drops privileges to that user before
# mkdir/copy/exec. The result: whatever user owns ./homecore-data
# on the host owns every file the container writes there. Operators
# don't need to set env vars or pre-chown anything — `mkdir
# homecore-data && docker compose up` just works.

set -e

HOME_DIR="${HOMECORE_HOME:-/homecore}"

# ─── Drop privileges to bind-mount owner ────────────────────────────
# Only does anything if we're running as root AND the home dir's
# owner is non-root. If the operator already set `user:` in compose,
# we're not root and this stage is a no-op.
if [ "$(id -u)" = "0" ]; then
    if [ ! -d "$HOME_DIR" ]; then
        mkdir -p "$HOME_DIR"
    fi
    target_uid=$(stat -c '%u' "$HOME_DIR")
    target_gid=$(stat -c '%g' "$HOME_DIR")

    if [ "$target_uid" = "0" ]; then
        # Brand-new bind that landed root-owned (Docker daemon created
        # the host dir before mount). Use the configured fallback
        # (default 1000:1000) and chown the dir so the host user can
        # read what we write.
        target_uid="${HOMECORE_UID:-1000}"
        target_gid="${HOMECORE_GID:-1000}"
        chown "$target_uid:$target_gid" "$HOME_DIR"
        echo "[appliance] bind-mount was root-owned; chowned $HOME_DIR to $target_uid:$target_gid"
    fi

    echo "[appliance] dropping privileges to $target_uid:$target_gid"
    exec su-exec "$target_uid:$target_gid" "$0" "$@"
fi

# ─── At this point we're running as the target non-root user ────────

DEFAULTS_DIR=/opt/homecore/defaults

CONFIG_DIR="$HOME_DIR/config"
DATA_DIR="$HOME_DIR/data"
RULES_DIR="$HOME_DIR/rules"
CORE_CONFIG="$CONFIG_DIR/homecore.toml"

BUNDLED_PLUGINS="hc-hue hc-wled hc-yolink hc-lutron hc-sonos \
                 hc-isy hc-zwave hc-caseta hc-thermostat hc-ecowitt"

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$RULES_DIR"

# ─── Seed core config ───────────────────────────────────────────────
if [ ! -f "$CORE_CONFIG" ]; then
    cp "$DEFAULTS_DIR/homecore.toml" "$CORE_CONFIG"
    echo "[appliance] seeded core config at $CORE_CONFIG"
fi

# ─── Seed per-plugin configs (regardless of enabled state) ──────────
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
echo "[appliance] starting hc-core with home=$HOME_DIR"
exec /usr/local/bin/homecore --home "$HOME_DIR" --config "$CORE_CONFIG"
