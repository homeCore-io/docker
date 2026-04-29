# Multi-host deployment

When hc-core lives on a different machine than its plugins. Common
shapes:

- A homelab with a dedicated "automation server" running hc-core,
  and plugins running on the host nearest the hardware (e.g. an
  RPi sitting next to a Z-Wave stick).
- An off-the-shelf appliance running a stripped-down hc-core, with
  plugin containers spread across whichever hosts have credentials
  for cloud APIs.
- A test/staging core on one box with production plugins still
  pointed at the production core elsewhere.

Single-host (everything on one machine) is the default the
top-level `compose.yaml` ships for. Use the templates here when you
need the split.

## Topology

```
host-A (10.0.10.20)        host-B (10.0.10.30)
─────────────────          ─────────────────
hc-core                    hc-hue
└── embedded broker        hc-sonos
    on 0.0.0.0:1883        └── connect to 10.0.10.20:1883
```

> **Security note.** The embedded broker enforces CONNECT auth only,
> not per-topic ACLs. Don't expose host A's port 1883 to the
> internet. For untrusted networks, run an external Mosquitto with
> proper ACL config — see the top-level README's *Advanced* section.

## Host A — `core-host/`

```sh
cp -r examples/multi-host/core-host ~/homecore && cd ~/homecore
mkdir homecore-data
docker compose up -d

cat homecore-data/INITIAL_ADMIN_PASSWORD
open http://10.0.10.20:8080
```

The compose file sets `HC_BROKER_BIND=0.0.0.0`; hc-core's entrypoint
sed-replaces the seeded config's `[broker] host` on first boot so the
broker accepts connections from the LAN. Subsequent restarts honor
any manual edits to `homecore-data/config/homecore.toml`.

## Host B — `plugin-host/`

```sh
cp -r examples/multi-host/plugin-host ~/homecore-plugins
cd ~/homecore-plugins

# Edit compose.yaml: replace __SET_HC_CORE_LAN_IP__ with host A's IP
$EDITOR compose.yaml

# Pre-create per-service host dirs (entrypoint matches whoever owns them)
mkdir hc-hue-data hc-sonos-data

docker compose up -d
```

Each plugin's `HC_BROKER_HOST` env injects the right `broker_host`
into its seeded `config.toml` on first boot — operator never edits
the broker line by hand.

After first boot, edit per-plugin config (Hue API key, Sonos host
hints, etc.):

```sh
$EDITOR hc-hue-data/config.toml
docker compose restart hc-hue
```

## Env knobs (first-boot only)

These envs are only consulted while the entrypoint is seeding a
fresh `<dir>/config.toml`. Once a config exists, the entrypoint
respects whatever's in it — env changes don't override existing
files. To move the broker later, edit the file directly and
`docker compose restart`.

| env | applies to | seeds | default |
|-----|-----------|-------|---------|
| `HC_BROKER_BIND` | hc-core | `[broker] host` in homecore.toml | unset → `127.0.0.1` |
| `HC_BROKER_HOST` | each plugin | `[homecore] broker_host` in plugin config | unset → `127.0.0.1` |
| `HC_BROKER_PORT` | each plugin | `[homecore] broker_port` | unset → `1883` |

## Re-seeding

If you need to re-apply env changes to an existing install (e.g.
the LAN IP of host A changed and you don't want to edit by hand):

```sh
docker compose down
rm <plugin>-data/config.toml      # nuke just the config, keep state
docker compose up -d              # entrypoint re-seeds with current env
```

(Or just sed-edit the file in place — usually quicker.)
