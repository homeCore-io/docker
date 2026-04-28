#!/bin/sh
# First-boot config seeder for any hc-* plugin.
#
# BINARY_NAME is baked into the image at build time. We expect:
#   /usr/local/bin/$BINARY_NAME           — the plugin binary
#   /opt/homecore/defaults/config.toml    — the bundled default config
#   /etc/homecore/                        — bind-mounted from the host

set -e

if [ -z "$BINARY_NAME" ]; then
    echo "[entrypoint] FATAL: BINARY_NAME is not set in the image" >&2
    exit 1
fi

CONFIG_DIR=/etc/homecore
CONFIG_FILE="$CONFIG_DIR/config.toml"
DEFAULT_CONFIG=/opt/homecore/defaults/config.toml

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
    echo "[$BINARY_NAME] seeded default config at $CONFIG_FILE — edit and restart"
fi

exec "/usr/local/bin/$BINARY_NAME" "$CONFIG_FILE"
