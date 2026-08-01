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

**The proxy is not a convenience.** The app calls `/api/v1` as a *relative*
path and core sends no CORS headers, so the API has to be same-origin with the
app. There is no supported shape where a browser talks to core directly.

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

### Deploying through a stack manager

Dockhand, Portainer and anything else that hands the file to the engine rather
than running `docker compose` will also work — but paste the file *whole*. The
`networks:` block at the bottom of `compose.yml` is load-bearing when deployed
this way, and dropping it produces the boot loop described under
[Troubleshooting](#troubleshooting).

There is no repo to clone in that shape, which is deliberate: nothing in these
files bind-mounts anything that only exists in a checkout.

## Which compose file

| File | Networking | Use it when |
|---|---|---|
| `compose.yml` | bridge | **Start here.** |
| `compose.host.yml` | host | You have Hue, Sonos, WLED, Roku or Ecowitt — or discovery found nothing. |
| `compose-dev.yml` | bridge | You want the `:dev` tag, rebuilt on every push to develop. |

The distinction that matters is **discovery**. Hue, Sonos, WLED and Roku find
devices over mDNS/SSDP, which is multicast — and a Docker bridge network does
not carry it. On `compose.yml` those plugins install and run happily and then
find nothing at all. Sonos also serves UPnP event callbacks and has to advertise
an address the speakers can reach back on, which a NATed container IP is not.

Plugins that reach out over ordinary TCP or HTTP — YoLink, Lutron, Caseta, ISY,
Z-Wave — are fine on the bridge setup, because outbound connections NAT out of
a container without help.

**Ecowitt is not one of them**, and used to be listed here as if it were. Two of
its three paths need more than outbound TCP:

- *Gateway discovery* is a UDP broadcast to `255.255.255.255:45000`. A bridge
  network does not forward broadcast any more than it forwards multicast, so
  `discover_gateways` returns nothing however many gateways are on the LAN.
- *Receiving* uploads means the gateway opens a connection **to** homeCore, on
  `[ecowitt].listen_port` (default `8888`). This file does not publish that
  port, so nothing outside the container can reach it — setting
  `bind_addr = "0.0.0.0"` alone is not enough here, which it would be on bare
  metal.
- *Polling* is the exception and works on the bridge unchanged: set
  `[ecowitt].gateway_ip` and the plugin fetches from the gateway over ordinary
  outbound HTTP.

So on `compose.yml`: set `gateway_ip`, or publish `8888` and set `bind_addr`.
On `compose.host.yml` all three work as documented.

`compose.host.yml` is Linux only. Docker Desktop on macOS and Windows runs
containers inside a VM, so host networking there does not reach the LAN's
multicast traffic and the file will not do what it exists for.

## Configuration

There is nothing to mount. The image seeds `config/homecore.toml` inside
`homecore-data` on first boot, and the default is correct as shipped: core
serves no UI (hc-web does), declares no plugins, and points at the signed
registry. Edit that file and `docker compose restart homecore`; it is yours
after first boot and is never overwritten.

### Ports

`HC_WEB_PORT` (default 3000) and `HC_API_PORT` (default 8080) move the stack off
a busy host without editing a file:

```sh
HC_WEB_PORT=8800 HC_API_PORT=8801 docker compose up -d
```

**They mean different things in the two networking modes**, which is worth
knowing before you change one:

| | `compose.yml` / `compose-dev.yml` (bridge) | `compose.host.yml` (host) |
|---|---|---|
| `HC_WEB_PORT` | Published side of `HC_WEB_PORT:80`. nginx stays on 80 inside. | The port nginx itself binds, straight on the host. |
| `HC_API_PORT` | Published side of `HC_API_PORT:8080`. Core stays on 8080 inside. | Tells nginx where core is. Core binds whatever `[server] port` says — set this to match. |

Host mode has no port mappings at all, so nothing gets remapped for you: if
something else owns a port, move it here *and* in core's config.

### Layout

Everything lives under the single bind-mount:

```
./homecore-data/
├── INITIAL_ADMIN_PASSWORD     printed on first boot; delete it after logging in
├── config/homecore.toml       seeded by the image on first boot; edit freely
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

## Troubleshooting

Both of these were real, and both point away from themselves — which is the only
reason they are worth a section.

### hc-web restarts forever with `host not found in upstream "homecore"`

Core is healthy; it starts, serves and logs nothing wrong. The half of the stack
that is *not* broken is the half that dies.

The containers landed on Docker's default `bridge` network, which has no name
resolution at all, so nginx could not resolve `homecore`. `docker compose up`
creates a per-project network with embedded DNS and never shows this; a stack
manager that hands the file to the engine can skip that step.

**Fix:** use the `networks:` block at the bottom of `compose.yml`. If you pasted
an excerpt into a stack manager, paste the whole file.

Since hc-web 0.1.8 nginx also resolves its upstream per request rather than at
config load, so an unreachable core is a `502` that recovers on its own instead
of a container that exits. The named network is still what makes the name
resolve in the first place.

### `cp: can't create '/homecore/config/homecore.toml/config.toml': Read-only file system`

A `homecore.toml` bind-mount that pointed at a file which only existed in a
clone. Deploy the same file without the repo and Docker helpfully created a
*directory* at that path, so core's seed copy had nowhere to land.

**Fix:** already gone — there is no config mount. Core 0.1.8 corrected the
image's own default, which is what the mount had been compensating for. If you
are carrying a local copy of an older compose file, delete the mount.

### The UI is unreachable but both containers are up

Check what is actually published: `docker compose ps`. Through v0.1.9 the web
mapping pointed at container port 3001 and nginx listens on 80, so the published
port refused connections. Fixed in docker v0.1.10.

### Discovery finds nothing

Expected on `compose.yml` for Hue, Sonos, WLED, Roku and Ecowitt — see [Which
compose file](#which-compose-file). Switch to `compose.host.yml`.

Ecowitt has a second option that needs no network change: set
`[ecowitt].gateway_ip` to the gateway's address and it polls over outbound HTTP
instead of discovering and receiving.

## Image tags

| Tag | Meaning |
|---|---|
| `:latest` | Most recent tagged release. What `compose.yml` tracks. |
| `:0.1.9` | A specific release, immutable. |
| `:dev` | Rebuilt on every push to develop. Mutable. |
| `:dev-<sha7>` | A specific develop build, immutable. |

**The three components version independently and their numbers do not agree.**
core, hc-web and this repo are each tagged on their own cadence, so `hc-core`
and `hc-web` are routinely several releases apart. Do not read a shared version
into them. `git tag` here lists this repo's; the image tags above are core's and
hc-web's own.

To pin a whole stack, check this repo out at a tag and set both image versions
in the compose file explicitly, rather than relying on `:latest` or on the
numbers lining up.

## Releasing

Nothing here is part of anyone's build recipe any more, so **this repo does not
need tagging before core** — or at all, for a core release.

`images/Dockerfile.core` used to be that recipe: homeCore's `release.yml` checked
this repo out at the ref `docker_repo_ref` named and built the published
`hc-core` image from it, which is why this repo had to be tagged first. Since
this repo carries no version of its own, those tags were empty re-cuts existing
only to satisfy that pin. The recipe moved to `docker/Dockerfile.core` in
homeCore-io/homeCore on 2026-08-01, so it is versioned with the binary it wraps
and core's tag alone reproduces its image. Core releases up to v0.1.13 were
built the old way and still resolve the tags they used, so nothing historical
breaks.

hc-web builds its own image from `clients/hc-web/Dockerfile` and always did;
nothing here was ever involved. Core works the same way now.

## What used to be here

An **appliance image** (`homecore-appliance`) baked core and every plugin into
one container. It is retired — the stack above replaces it. Existing images
remain in GHCR, so anything still running one keeps working, but no new ones are
published.

There were also `Dockerfile.plugin` and a multi-host example running each plugin
as its own container. Plugins ship as signed registry artifacts now, so neither
had a consumer.

`images/` held `Dockerfile.core` and `entrypoint-core.sh`, the recipe for the
published core image, until 2026-08-01. They live in homeCore-io/homeCore under
`docker/` now — with the binary they wrap, rather than in a repo that had to be
tagged in lockstep to record which recipe built what.
