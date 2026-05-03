# Dockerfile templates

Optional Dockerfiles for use cases the canonical release pipeline
doesn't cover. **Not** used by CI / not used to publish images to
ghcr.io — those go through `../images/`.

## When to reach here vs `../images/`

| You want… | Use… |
|---|---|
| The image that ghcr.io ships | `../images/Dockerfile.{core,plugin,appliance}` |
| To build a local image from a prebuilt musl binary | `../images/Dockerfile.plugin` (set up the build context with the binary already in it) |
| To build a local image **from source** in one step, without prebuilding the binary | the templates below |

## Files

### `Dockerfile.plugin-from-source`

Generic Debian-based template that compiles any hc-* plugin from
source via `cargo build --release` inside the container.
Parameterized by `PLUGIN_NAME` build arg.

Use this when:
- you want a one-step `docker build` that produces a working
  container without prebuilding the plugin binary first;
- the canonical Alpine path is fighting back with musl / OpenSSL
  weirdness during local iteration;
- you're testing an unreleased plugin source tree and don't want
  to wire it through the release workflow.

Don't use this for shipping — the canonical Alpine
`../images/Dockerfile.plugin` is what the release pipeline uses
and what produces the reproducible, multi-arch ghcr.io images.

Usage example, run from a directory containing one or more plugin
source trees as siblings (typically the meta-layout's `plugins/`
dir):

```sh
docker build \
    -f /path/to/docker/templates/Dockerfile.plugin-from-source \
    --build-arg PLUGIN_NAME=hc-hue \
    -t hc-hue:from-source \
    /path/to/plugins/
```

See the comment block at the top of the Dockerfile for full
options + runtime-mount conventions.
