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
own build uses. By default it targets what official presto-native builds ship
(their Makefile defaults `CPU_TARGET` to `avx` on x86_64; arm builds use the
generic `aarch64` baseline), so the plugin is compatible with the official
presto-native images out of the box.

Set the `CPU_TARGET` environment variable to target a worker built with
different flags. It takes one of the keywords below — not raw compiler flags;
the helper expands the keyword to the same flag set the worker's build uses
(shown in the Flags column). Pick the value the target Presto worker was built
with:

| `CPU_TARGET` | Architecture   | Flags                                        |
|--------------|----------------|----------------------------------------------|
| (blank)      | any            | Official presto-native default: `avx` on x86_64; auto-detect elsewhere (Linux arm → `aarch64`) |
| `avx`        | x86_64         | `-mavx2 -mfma -mavx -mf16c -mlzcnt -mbmi2`   |
| `sse`        | x86_64         | `-msse4.2`                                   |
| `aarch64`    | arm64 (Linux)  | `-march=armv8-a+crc+crypto` (see note)       |
| `arm64`      | Apple Silicon  | `-mcpu=apple-m1+crc`                         |

Note: the two variables compose rather than compete. `CPU_TARGET` selects the
architecture flag family; `ARM_BUILD_TARGET` is a modifier consulted only
inside the arm family — with `avx`, `sse`, or `arm64` it has no effect. On arm
(`CPU_TARGET=aarch64` or auto-detection), `ARM_BUILD_TARGET` picks between
upstream's two arm build styles: `common` — the default,
`-march=armv8-a+crc+crypto`, upstream's portable baseline: it runs on any
armv8-a machine with the CRC and crypto extensions, which all server-class arm
cores (Neoverse, Graviton, Ampere) provide — and `local`,
which tunes for the build machine's detected Neoverse core (`-mcpu=neoverse-*`,
including that core's architecture extensions). Use `local` when the build
machine's core matches the deployment hardware — e.g. when packaging directly
on the production server or an identical machine; like `CPU_TARGET`, it's
forwarded into the packaging container. Keep `common` for artifacts that must
run on unknown or mixed arm hardware: core-specific extensions crash (SIGILL)
on other cores. (Upstream's helper defaults to `local` when the variable is
unset; our CMake configure pins `common` so default builds are portable.)
The CMake configure logs the resolved flags (`Target-CPU flags (get_cxx_flags)`)
so you can verify what a build used.

Locally, set it on either build path (the package build forwards it into the
container):

```bash
CPU_TARGET=sse task velox-connector:build  # dev build
CPU_TARGET=sse task package                # package build
```

In CI, triggering `build-packages.yaml` manually (workflow dispatch) exposes
per-architecture inputs — `amd64_cpu_target`, `arm64_cpu_target`, and
`arm64_build_target` — each applied only to the matching architecture's build,
so an input can never affect the other architecture. Blank inputs — and
push-triggered builds — use the official presto-native defaults. Changing the
flags re-runs the CMake configure, and the changed flags rebuild the affected
objects.

### Finding the right value

Folly encodes the F14 ABI mode in a symbol name, so the Presto worker binary
that will load the plugin can tell you directly:

```bash
nm -DC /path/to/presto_server | grep F14LinkCheck
```

| Symbol in the worker                 | Worker was built with | `CPU_TARGET` to use              |
|--------------------------------------|-----------------------|----------------------------------|
| `F14LinkCheck<(F14IntrinsicsMode)2>` | AVX2                  | `avx`                            |
| `F14LinkCheck<(F14IntrinsicsMode)1>` | SSE / NEON only       | `sse` (x86_64), `aarch64` (arm64) |

The same command on `libclp-plugin-velox-connector.so` shows the mode the
plugin expects, as an undefined symbol the worker must provide; a mismatch
fails at plugin load with an unresolved `F14LinkCheck<...>` error naming the
expected mode. The F14 link check is the enforced part of the contract —
matching the worker's full flag set is still the safe rule for the rest of the
shared inline code.
