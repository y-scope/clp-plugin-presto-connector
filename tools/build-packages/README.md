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

A thin wrapper over `./tools/build-packages/build-packages.sh` (call that directly if `go-task` isn't installed). Both accept `--output DIR`, `--version VER`, and `--with-ca-certs`; with the task, put `--` before the flags: `task package -- --output DIR`.

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

## Target-CPU flags

The worker plugin must be compiled with the same target-CPU flags as the Presto
worker that loads it: Folly's F14 hash table bakes the enabled CPU features into
its ABI and aborts the worker at plugin load on a mismatch. The velox-connector
CMake configure derives its flags with the same `get_cxx_flags` helper Presto's
own build uses, so both auto-detect the build machine's CPU by default.

Set the `CPU_TARGET` environment variable to build for a different target than
the build machine — pick the value the target Presto worker was built with:

| `CPU_TARGET` | Architecture   | Flags                                        |
|--------------|----------------|----------------------------------------------|
| (blank)      | any            | Auto-detect the build machine's CPU          |
| `avx`        | x86_64         | `-mavx2 -mfma -mavx -mf16c -mlzcnt -mbmi2`   |
| `sse`        | x86_64         | `-msse4.2`                                   |
| `aarch64`    | arm64 (Linux)  | `-march=armv8-a+crc+crypto` (see note)       |
| `arm64`      | Apple Silicon  | `-mcpu=apple-m1+crc`                         |

Note: with `CPU_TARGET=aarch64`, additionally setting `ARM_BUILD_TARGET=local`
tunes for the build machine's detected Neoverse core (`-mcpu=neoverse-*`)
instead of the generic armv8-a baseline.

Locally, set it on either build path (the package build forwards it into the
container):

```bash
CPU_TARGET=sse task velox-connector:build  # dev build
CPU_TARGET=sse task package                # package build
```

In CI, triggering `build-packages.yaml` manually (workflow dispatch) exposes
`amd64_cpu_target` and `arm64_cpu_target` inputs, each applied to the matching
architecture's build. Blank inputs — and push-triggered builds — auto-detect the
runner's CPU. Changing `CPU_TARGET` re-runs the CMake configure, and the changed
flags rebuild the affected objects.
