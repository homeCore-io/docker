# homeCore — Docker distribution

Two artifacts ship from this repo:

1. **Multi-container compose** — hc-core + each plugin as its own
   service, glued together via compose `include:`. The recommended
   shape for any real install. Documented below.
2. **All-in-one appliance image** — every binary baked into a single
   container. Quick to spin up for evaluation; not the recommended
   shape long-term. See [Appliance image](#appliance-image) below.

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

## Image sizing

These images target as small as possible while staying on alpine (vs.
distroless / scratch — alpine keeps a shell + busybox for entrypoint
flexibility and `docker exec` debugging).

| layer                                      |   typical |
| ------------------------------------------ | --------: |
| `alpine:3.20` base                         |    ~7 MB  |
| `ca-certificates` + `tini`                 |    ~1 MB  |
| plugin binary (stripped, LTO, musl-static) | ~25–30 MB |
| hc-core binary (stripped, LTO, musl-static)| ~30–40 MB |
| Leptos WASM `dist/` (release)              |  ~1–2 MB  |

Targets: **plugin image ~30–40 MB**, **core image ~40–55 MB** compressed.

*(Measured: hc-hue@dev-a943e83 is **35.4 MB** multi-arch on ghcr.io.
Rust binaries with reqwest + tokio + tracing + rustls + flate2 land
heavier than a naive estimate suggests — the `[profile.release]`
strip + thin LTO already extract most of what's available without
reaching for UPX or distroless.)*

### Biggest lever: Cargo release profile

The single highest-impact optimization lives in each plugin / hc-core
repo's root `Cargo.toml`, NOT in the Dockerfile. Add to every workspace:

```toml
[profile.release]
strip       = "symbols"
lto         = "thin"
codegen-units = 1
panic       = "abort"   # optional: smaller, no unwind tables
```

Without `strip`, every Rust binary ships with debug symbols → ~30–50%
bloat. The Dockerfiles run `strip --strip-all` as a fallback in case
the upstream binary still has symbols, but doing it at build time is
faster and keeps the artifact useful elsewhere (GH release tarball).

### What we're NOT doing (and why)

- **scratch / distroless static** — drop ~7 MB but lose the busybox
  shell that `entrypoint-{core,plugin}.sh` relies on. We'd have to
  fold first-boot config seeding into each binary; deferred.
- **UPX-compressed binaries** — 3–4× smaller on disk but slower
  startup + flagged by some AV; not worth it for a long-running
  daemon.
- **Pre-gzipping the WASM bundle** — only pays off if hc-core's
  static layer is wired to serve `Content-Encoding: gzip` from `.gz`
  twins (tower-http `.precompressed_gzip()`). Not currently confirmed
  on the serve side; revisit when wiring trunk's `--release` step
  into homeCore's `release.yml`.

## Appliance image

For evaluation / "kick the tires" use, an all-in-one image bundles
hc-core + every CI-active plugin into one container.

**Single bind-mount layout.** Everything operator-mutable (configs,
state, rules, logs, the first-boot admin password file) lives under
one directory: `/homecore` inside the container, whichever host path
you mount. One mount, one place to look.

```sh
docker run --rm -p 8080:8080 -p 1883:1883 \
    -v $PWD/homecore-data:/homecore \
    ghcr.io/homecore-io/homecore-appliance:0.1.0
```

After first boot the host-side `homecore-data/` contains:

```
homecore-data/
├── INITIAL_ADMIN_PASSWORD       ← printed on first boot, delete after login
├── config/
│   ├── homecore.toml            ← edit and restart
│   ├── hc-hue/config.toml
│   └── ... (per enabled plugin)
├── data/
│   ├── state.redb
│   └── history.db
├── rules/
├── logs/
├── jwt_secret                   ← auto-managed
└── ui -> /opt/homecore/ui       ← symlink to baked WASM bundle
```

The container starts hc-core (with its embedded broker) plus every
plugin listed in `$HC_PLUGINS`. Default is all 10. Narrow it down:

```sh
docker run -e HC_PLUGINS="hc-hue hc-sonos" \
    -v $PWD/homecore-data:/homecore \
    ghcr.io/homecore-io/homecore-appliance:0.1.0
```

Web UI: http://localhost:8080. First-boot admin credentials are at
`./homecore-data/INITIAL_ADMIN_PASSWORD` (and printed to
`docker compose logs`). Delete that file after you change the password.

The appliance image's tag matches this repo's tag — `:0.1.0` of the
appliance bundles the `:0.1.0` of hc-core and each plugin. For test
builds, `workflow_dispatch` the *Appliance image* workflow with custom
component/appliance tags.

**When NOT to use it:**

- For real device deployment with multiple plugins — use the
  multi-container compose path. Each plugin in its own container is
  cleaner to upgrade, restart, and scope failures.
- For ARM-only hardware that's pinned to ARMv7 — the appliance is
  amd64 + arm64 only.

**How it's built:** `images/Dockerfile.appliance` is a multi-stage
Dockerfile that pulls binaries OUT of each per-component image:

```dockerfile
FROM ghcr.io/homecore-io/hc-core:${COMPONENT_TAG}  AS core-stage
FROM ghcr.io/homecore-io/hc-hue:${COMPONENT_TAG}   AS hue-stage
# … one per plugin
FROM alpine:3.20
COPY --from=core-stage /usr/local/bin/homecore /usr/local/bin/
# … etc
```

Multi-arch comes for free — buildx resolves each `FROM` to the right
arch via the component's manifest. Build takes ~2 min (no Rust
compilation, just COPY layers).

## Advanced: external Mosquitto broker

Not included here. The embedded broker does CONNECT auth only; if you
need per-client topic ACL enforcement, run an external Mosquitto and
point hc-core + every plugin at it via their `config.toml`'s broker
section. See `mqttAuthzPlan.md` in the homeCore repo.
