#!/bin/sh
# Per-plugin (per-service compose) entrypoint.
#
# Single-base-dir layout under $HOMECORE_HOME (default /homecore).
# Container starts as root, looks at the bind-mount's owner, and
# su-execs to that user before any mkdir / write / exec. Operator
# just `mkdir <plugin>-data && docker compose up`.
#
# Plugin binaries take a single positional config-path argument
# (per the plugin SDK's main.rs convention). They don't have a
# base_dir concept; we just point them at $HOMECORE_HOME/config.toml.

set -e

if [ -z "$BINARY_NAME" ]; then
    echo "[entrypoint] FATAL: BINARY_NAME is not set in the image" >&2
    exit 1
fi

HOME_DIR="${HOMECORE_HOME:-/homecore}"

# ─── Drop privileges to bind-mount owner ────────────────────────────
if [ "$(id -u)" = "0" ]; then
    if [ ! -d "$HOME_DIR" ]; then
        mkdir -p "$HOME_DIR"
    fi
    target_uid=$(stat -c '%u' "$HOME_DIR")
    target_gid=$(stat -c '%g' "$HOME_DIR")

    if [ "$target_uid" = "0" ]; then
        target_uid="${HOMECORE_UID:-1000}"
        target_gid="${HOMECORE_GID:-1000}"
        chown "$target_uid:$target_gid" "$HOME_DIR"
        echo "[$BINARY_NAME] bind-mount was root-owned; chowned $HOME_DIR to $target_uid:$target_gid"
    fi

    echo "[$BINARY_NAME] dropping privileges to $target_uid:$target_gid"
    exec su-exec "$target_uid:$target_gid" "$0" "$@"
fi

# ─── Running as the target non-root user ────────────────────────────

DEFAULTS_DIR=/opt/homecore/defaults
CONFIG_FILE="$HOME_DIR/config.toml"

mkdir -p "$HOME_DIR"

# ─── Seed config ────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$DEFAULTS_DIR/config.toml" "$CONFIG_FILE"
    echo "[$BINARY_NAME] seeded default config at $CONFIG_FILE"

    # Optional first-boot env injection — useful for the multi-host
    # shape where the plugin runs on a different machine than hc-core.
    # Only fires on FIRST boot; subsequent restarts respect operator
    # edits to the config file.
    if [ -n "$HC_BROKER_HOST" ]; then
        sed -i "s|^broker_host *= *\".*\"|broker_host = \"$HC_BROKER_HOST\"|" "$CONFIG_FILE"
        echo "[$BINARY_NAME] set broker_host = \"$HC_BROKER_HOST\" (from env)"
    fi
    if [ -n "$HC_BROKER_PORT" ]; then
        sed -i "s|^broker_port *= *.*|broker_port = $HC_BROKER_PORT|" "$CONFIG_FILE"
        echo "[$BINARY_NAME] set broker_port = $HC_BROKER_PORT (from env)"
    fi
fi

# ─── Start plugin ───────────────────────────────────────────────────
echo "[$BINARY_NAME] starting with config=$CONFIG_FILE"
exec "/usr/local/bin/$BINARY_NAME" "$CONFIG_FILE"
