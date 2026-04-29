#!/bin/sh
# hc-core (per-service compose) entrypoint.
#
# Single-base-dir layout: everything operator-mutable under
# $HOMECORE_HOME (default /homecore). Container starts as root, looks
# at the bind-mount's owner, and su-execs to that user before any
# mkdir / write / exec. Operators just `mkdir homecore-data &&
# docker compose up` — no env vars, no pre-chown ritual.
#
# In the multi-container compose shape, this image runs ONE process:
# hc-core itself. Plugin processes run in their own containers and
# connect over MQTT — see compose.<plugin>.yaml fragments.

set -e

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
        echo "[hc-core] bind-mount was root-owned; chowned $HOME_DIR to $target_uid:$target_gid"
    fi

    echo "[hc-core] dropping privileges to $target_uid:$target_gid"
    exec su-exec "$target_uid:$target_gid" "$0" "$@"
fi

# ─── Running as the target non-root user ────────────────────────────

DEFAULTS_DIR=/opt/homecore/defaults
CONFIG_DIR="$HOME_DIR/config"
DATA_DIR="$HOME_DIR/data"
RULES_DIR="$HOME_DIR/rules"
CORE_CONFIG="$CONFIG_DIR/homecore.toml"

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$RULES_DIR"

# ─── Seed core config ───────────────────────────────────────────────
if [ ! -f "$CORE_CONFIG" ]; then
    cp "$DEFAULTS_DIR/config.toml" "$CORE_CONFIG"
    echo "[hc-core] seeded default config at $CORE_CONFIG"
fi

# ─── Start hc-core ──────────────────────────────────────────────────
echo "[hc-core] starting with home=$HOME_DIR"
exec /usr/local/bin/homecore --home "$HOME_DIR" --config "$CORE_CONFIG"
