#!/bin/sh
# First-boot config seeder for hc-core.
#
# If /etc/homecore/config.toml does not exist (typical on first run with a
# fresh bind-mount), copy the bundled default into place. Subsequent boots
# preserve the user's edits.

set -e

CONFIG_DIR="${HC_CONFIG%/*}"
CONFIG_FILE="$HC_CONFIG"
DEFAULT_CONFIG=/opt/homecore/defaults/config.toml

mkdir -p "$CONFIG_DIR" "$HC_DATA_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
    echo "[homecore] seeded default config at $CONFIG_FILE — edit and restart"
fi

exec /usr/local/bin/homecore "$CONFIG_FILE"
