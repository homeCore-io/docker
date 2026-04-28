# homeCore — Docker distribution

Multi-container compose setup for running [homeCore](https://homecore.io)
plus the plugins you want, using the embedded MQTT broker.

For an all-in-one container (good for evaluating, not for running real
devices long-term), see `Dockerfile.appliance` at the homeCore meta repo
root instead — that's the "single image, everything baked in" path.

This repo is the **multi-container path**: hc-core in one container,
each plugin in its own, glued together with compose `include:`.

---

## Quick start

```sh
git clone https://github.com/homeCore-io/docker.git homecore-docker
cd homecore-docker

# 1. Pick the plugins you want by uncommenting them in compose.yaml.
$EDITOR compose.yaml

# 2. Bring it up. First boot seeds default configs into ./config/.
docker compose up -d

# 3. Edit the seeded configs.
$EDITOR config/homecore/config.toml
$EDITOR config/hc-hue/config.toml   # if you enabled Hue

# 4. Restart to pick up your edits.
docker compose restart
```

The web UI is on http://localhost:8080. First-boot admin credentials
are printed to `docker compose logs homecore`.

## Layout

```
./compose.yaml             base — just hc-core
./compose.<plugin>.yaml    one fragment per plugin (include: as needed)
./images/                  Dockerfiles + entrypoints (only used if you
                           want to build images locally instead of
                           pulling from ghcr.io)
./config/                  bind-mounted into each container; first boot
                           seeds defaults here. EDIT THESE.
./data/                    bind-mounted state (audit DB, redb, etc.)
```

`./config/` and `./data/` are gitignored — they're your local state.

## Network

Every service uses `network_mode: host`. This is required for:

- mDNS / SSDP / UPnP discovery (Hue, Sonos, WLED, ISY, Lutron Caseta)
- the embedded MQTT broker being reachable by IoT devices on the LAN
- the simplest possible plugin → core wiring (`mqtt://127.0.0.1:1883`)

Trade-off: host networking is Linux-specific and assumes one homeCore
deployment per host. For multi-host (one core, plugins elsewhere), see
the "Bridge networking" section below — not yet drafted.

## Versioning

This repo's tags pin known-good combos of all the underlying images.
`git checkout v0.1.0` of this repo gives you compose files that point
at `ghcr.io/homecore-io/hc-*:0.1.0` for every service. Bump together,
not individually.

## Building images locally

By default, compose pulls from `ghcr.io/homecore-io/hc-*`. To build
locally instead (e.g. you're testing a feature branch), point each
service at `images/Dockerfile.plugin` via a compose override — see
`images/README.md` (TODO).

## Advanced: external Mosquitto broker

Not included here. The embedded broker does CONNECT auth only; if you
need per-client topic ACL enforcement, run an external Mosquitto and
point hc-core + every plugin at it via their `config.toml`'s broker
section. See `mqttAuthzPlan.md` in the homeCore repo.
