# homeCore — new-UI test stack

Run the **new (Flutter) web interface** + **hc-core**, with plugins installed
at runtime from the **plugin registry**. Two containers, one command.

```
mkdir homecore-data
docker compose up -d
cat homecore-data/INITIAL_ADMIN_PASSWORD     # first-boot admin password
```

Open **http://<host-ip>:3000**, sign in, and go to **Plugins → Add** to install
plugins from the registry.

## What's in here

| file | purpose |
|---|---|
| `compose.yml` | `homecore` (hc-core: API + broker) + `hc-web` (the new UI, proxies `/api` to core) |
| `homecore.toml` | core config with a `[registry]` block (points at `homecore.io/registry`); core's own UI is off since hc-web serves it |

Plugins are **not** bundled — they install from the registry and run as managed
children of hc-core. Installed plugins live under `homecore-data/plugins/` and
persist across restarts.

## Prerequisites / caveats

1. **ghcr pull access.** The images are `ghcr.io/homecore-io/hc-core:dev` and
   `ghcr.io/homecore-io/hc-web:dev`. If the packages aren't public, the runner
   needs `docker login ghcr.io` with a token that can read them.
2. **`hc-core:dev` must be the build that includes registry-install.** It's
   rebuilt from `core` develop — after a push it takes a few minutes for CI to
   publish the new `:dev` image. `docker compose pull` to get the latest.
3. **The registry needs published plugins to install.** The production registry
   is served but only has whatever plugins have been released to it. Until at
   least one plugin is published (a plugin `v*` tag release, which signs the
   index), "Plugins → Add" will show an empty/unavailable registry.

## Networking

Bridge network by default (simplest — hc-web finds core by service name). For
**mDNS/SSDP plugin auto-discovery** (WLED/Hue/Sonos), the broker + plugins must
be on the host network: add `network_mode: host` to the `homecore` service (and
remove its `ports:`), then set hc-web's `HOMECORE_URL` to `http://<host-ip>:8080`.

## Self-hosting the registry

Point `[registry].url` in `homecore.toml` at any static host serving
`index.json` + `index.json.sig`, and set `public_key` to that registry's signing
key. See the `homeCore-io/registry` repo.
