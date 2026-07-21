# CLP Presto connector packaging

This directory builds installable `.deb`, `.rpm`, and `.tar.gz` artifacts, plus a busybox
init-container installer image, for the CLP Presto connector (coordinator + worker) on
`amd64` and `arm64`.

CI packaging runs `tools/build-packages/internal/container/build-artifacts.sh`
through `.github/workflows/build-packages.yaml`. Local builds use
`build-packages.sh`, which resolves the build-env image and invokes the same
container-side script.

Supported package version format: must start with a digit and use only
`[0-9A-Za-z.+~-]`.

For command options, run `--help` on the relevant entry point.

Default outputs are written to `./packages`.
`coordinator/` contains `clp-plugin-presto-connector.jar`; `worker/` contains
`libclp-plugin-velox-connector.so` and bundled non-system runtime `.so` files.

## Layout

* `build-dependency-image.sh` — Resolves and prints the build-env image
  reference; also usable standalone for one-off container runs.
* `build-packages.sh` — Local entry point: resolves the build-env image,
  prepares the build cache and CA trust, and runs the container-side build.
* `dependency-image/` — Build-env image definition: the `Dockerfile`,
  `utils.sh` (image-tag hash derivation and Docker build helpers, shared with
  the `build-dependency-image` CI workflow), and `use-host-ca.sh` (exposes a
  host CA bundle to the image's networked build steps).
* `internal/` — Implementation used by the entry points and CI, not meant to
  be invoked by users directly.
  * `build-cache/` — Host/container script pair behind the persistent local
    build cache: `host.sh` creates the `.cache/` layout (`ccache/` and
    `maven/` shared across build-env revisions; `build/<key>/` and
    `fetchcontent/<key>/` namespaced per revision), and `container.sh` points
    ccache, CMake FetchContent, and Maven at it inside the container.
    Local-only; CI builds run without it.
  * `ca-trust/` — Reusable library for propagating host CA certificates into
    containerized builds behind TLS-intercepting proxies without persisting
    them in images, caches, or artifacts; see its
    [README](internal/ca-trust/README.md). Expected to move into
    `yscope-dev-utils` and be imported back from there.
  * `container/` — `build-artifacts.sh`, the container-side implementation
    shared by local and CI builds: validates dependency pins, builds the
    worker plugin, provisions the pinned Presto commit's Maven artifacts and
    builds the coordinator plugin, stages one payload (bundling the worker's
    non-system runtime `.so` dependencies), and emits it as `.deb`, `.rpm`,
    and relocatable `.tar.gz`.
* `package-specs/` — `.deb` control-file template and `.rpm` spec consumed by
  `build-artifacts.sh`.

## Local usage

```bash
task package
```

A thin wrapper over `./tools/build-packages/build-packages.sh` (call that directly if `go-task` isn't installed). Both accept `--output DIR`, `--version VER`, and `--with-ca-certs`; with the task, put `--` before the flags: `task package -- --output DIR`.

### Installer image

`task package` also builds and loads a busybox init-container image that bundles both plugins. Its entrypoint copies each component into a mounted volume named by `COORDINATOR_PLUGIN_INSTALL_PATH` / `WORKER_PLUGIN_INSTALL_PATH` (set either or both):

```bash
docker run --rm -e WORKER_PLUGIN_INSTALL_PATH=/plugins -v "$(pwd)/plugins:/plugins" \
  ghcr.io/y-scope/clp-plugin-presto-connector:<version>-<arch>
```

Run `build-installer-init-image.sh --help` to build it standalone from any package tarball.

The build runs inside a hash-tagged **build-env image** (`env-<hash>`) based on
`manylinux_2_28`. `build-dependency-image.sh` resolves it from the local Docker
cache, this repository's GHCR package, or a local build, reusing the cached
image on later runs.

Build state is cached under `.cache/` (`maven/`, `ccache/`,
`fetchcontent/<hash>/`, and `build/<hash>/` for persisted CMake/build state),
shared across build-env revisions. `.cache/build/<hash>/` is the container's
build output directory and is distinct from the repository's separate top-level
`build/` directory used by non-container local dev builds. The local wrapper
runs the container with the invoking host UID/GID, so it does not create
root-owned files; any root-owned files in `.cache/`, `build/`, or
`presto-connector/target/` are leftovers from earlier privileged or CI builds,
while `packages/` is owned by the invoking user.

### Prerequisites

Docker with buildx (usable without `sudo`), git, `sha256sum` or `shasum`, and
~10 GB free disk for the build-env image.
