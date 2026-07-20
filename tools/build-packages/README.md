# CLP Presto connector packaging

This directory builds installable `.deb`, `.rpm`, and `.tar.gz` artifacts for the CLP
Presto connector (coordinator + worker) on `amd64` and `arm64`.

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

## Local usage

```bash
task package
```

A thin wrapper over `./tools/build-packages/build-packages.sh` (call that
directly if `go-task` isn't installed). Both accept `--output DIR` and
`--version VER`; with the task, put `--` before the flags:
`task package -- --output DIR`.

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

### Host CA trust

Local builds stage the host CA bundle and a Java PKCS#12 trust store so Maven reaches HTTPS repositories through corporate TLS gateways.
Staged stores are temporary, never enter image layers, caches, or packages, and CI is unaffected (no `CA_TRUST_DIR`).
See [internal/ca-trust/README.md](internal/ca-trust/README.md) for details.

### Prerequisites

Docker with buildx (usable without `sudo`), git, `sha256sum` or `shasum`, and
~10 GB free disk for the build-env image.
