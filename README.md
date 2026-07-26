# homeCore — Docker distribution

The images and compose files that run homeCore.

```
browser ─▶ hc-web ─┬─ /            the Flutter web UI
                   └─ /api/v1/* ──▶ hc-core ──▶ plugins (child processes)
                                       │
                                       └─ embedded MQTT broker
```

Two containers, and that is the whole stack.

| Image | What it is |
|---|---|
| `ghcr.io/homecore-io/hc-core` | The REST/WebSocket API and the embedded MQTT broker. No UI, no plugins. |
| `ghcr.io/homecore-io/hc-web` | The Flutter web UI. nginx serves the app and reverse-proxies `/api/v1/*` to core. |

**Plugins are not containers.** Install them from the UI — Plugins → Add — and
core downloads a signed artifact from the [plugin
registry](https://github.com/homeCore-io/registry), verifies its ed25519
signature, and runs it as a child process. Adding hardware support never means
editing a compose file.

---

## Quick start

```sh
git clone https://github.com/homeCore-io/docker.git homecore-docker
cd homecore-docker

mkdir homecore-data          # as your user — see "File ownership" below
docker compose up -d

cat homecore-data/INITIAL_ADMIN_PASSWORD
```

Open `http://<host-ip>:3000`, log in with `admin` and that password, then go to
Plugins → Add and install what your hardware needs.

## Which compose file

| File | Networking | Use it when |
|---|---|---|
| `compose.yml` | bridge | **Start here.** |
| `compose.host.yml` | host | You have Hue, Sonos, WLED or Roku — or discovery found nothing. |
| `compose-dev.yml` | bridge | You want the `:dev` tag, rebuilt on every push to develop. |

The distinction that matters is **discovery**. Hue, Sonos, WLED and Roku find
devices over mDNS/SSDP, which is multicast — and a Docker bridge network does
not carry it. On `compose.yml` those plugins install and run happily and then
find nothing at all. Sonos also serves UPnP event callbacks and has to advertise
an address the speakers can reach back on, which a NATed container IP is not.

Plugins that reach out over ordinary TCP or HTTP — YoLink, Lutron, Caseta, ISY,
Z-Wave, Ecowitt — are fine on the bridge setup.

`compose.host.yml` is Linux only. Docker Desktop on macOS and Windows runs
containers inside a VM, so host networking there does not reach the LAN's
multicast traffic and the file will not do what it exists for.

## Configuration

`homecore.toml` in this repo is bind-mounted read-only to
`/homecore/config/homecore.toml`. It is a complete core config with two things
set for this deployment shape:

- `[web_admin] enabled = false` — hc-web serves the UI, so core only serves the
  API.
- `[registry]` — the signed plugin registry and its public key.

Edit it and `docker compose restart homecore`. To use the image's built-in
default instead, drop the `./homecore.toml` bind-mount from the compose file.

Everything else lives under the single bind-mount:

```
./homecore-data/
├── INITIAL_ADMIN_PASSWORD     printed on first boot; delete it after logging in
├── config/homecore.toml       (bind-mounted from ./homecore.toml)
├── config/plugins/            per-plugin configs, seeded on install
├── data/state.redb            device registry
├── data/history.db            time-series history
├── data/jwt_secret            generated, 0600
├── plugins/<id>/<version>/    installed plugin binaries, previous versions kept
├── rules/                     automation rules, hot-reloaded
└── logs/
```

### File ownership

`mkdir homecore-data` as yourself is the entire setup. The entrypoint starts as
root, reads the bind-mount's owner UID, and `su-exec`s to it before writing
anything — so files stay editable without sudo. If the directory does not exist
Docker creates it root-owned, and the entrypoint chowns it to
`HOMECORE_UID:HOMECORE_GID` (default `1000:1000`).

### The MQTT broker

Core embeds an MQTT broker on 1883. It is **not** published by default: it binds
loopback, and plugins are children of core in the same network namespace, so
nothing outside the container needs to reach it.

Publish it only if LAN devices — Tasmota, Shelly, ESPHome — publish to it
directly. That also means setting `[broker] host = "0.0.0.0"` and adding
`[[broker.clients]]` credentials. Core refuses to start if you bind the broker
to a non-loopback address with no clients configured, rather than quietly
running an open broker; `HC_ALLOW_ANONYMOUS_REMOTE_BROKER=1` overrides that if
you genuinely mean it.

## Image tags

| Tag | Meaning |
|---|---|
| `:latest` | Most recent tagged release. What `compose.yml` tracks. |
| `:0.1.6` | A specific release, immutable. |
| `:dev` | Rebuilt on every push to develop. Mutable. |
| `:dev-<sha7>` | A specific develop build, immutable. |

To pin the whole stack, `git checkout v0.1.6` here and use the compose file at
that tag with the matching image versions.

## Releasing

`images/Dockerfile.core` is the recipe for the published `hc-core` image, but
this repo does not build it — homeCore's own `release.yml` does, checking this
repo out at the ref its `docker_repo_ref` names. That makes this repo part of
core's build recipe, which is why **this repo is tagged before core**. If the
tag is missing, core's release fails with a message saying so rather than
silently building against `develop`.

hc-web builds its own image from `clients/hc-web/Dockerfile`; nothing here is
involved.

## What used to be here

An **appliance image** (`homecore-appliance`) baked core and every plugin into
one container, and this repo had a workflow to build it. It is retired — the
stack above replaces it. Existing appliance images remain in GHCR, so anything
still running one keeps working, but no new ones are published.

There were also `Dockerfile.plugin` and a multi-host example running each plugin
as its own container. Plugins ship as signed registry artifacts now, so neither
had a consumer.
