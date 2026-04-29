#!/bin/sh
# homeCore appliance entrypoint.
#
# - Seeds default configs into /etc/homecore on first boot (volumed
#   from the host so subsequent runs preserve the operator's edits).
# - Starts hc-core (which embeds the MQTT broker) in the background.
# - Starts each plugin listed in $HC_PLUGINS in the background.
# - Waits on hc-core; if hc-core exits, the container exits.
#
# tini handles PID-1 signal forwarding + zombie reaping for the
# background plugins.

set -e

CONFIG_DIR=/etc/homecore
DEFAULTS_DIR=/opt/homecore/defaults
DATA_DIR="${HC_DATA_DIR:-/var/lib/homecore}"

mkdir -p "$CONFIG_DIR" "$DATA_DIR"

# ─── Seed core config ───────────────────────────────────────────────
if [ ! -f "$CONFIG_DIR/config.toml" ]; then
    cp "$DEFAULTS_DIR/homecore.toml" "$CONFIG_DIR/config.toml"
    echo "[appliance] seeded core config at $CONFIG_DIR/config.toml"
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
echo "[appliance] starting hc-core"
/usr/local/bin/homecore "$CONFIG_DIR/config.toml" &
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
