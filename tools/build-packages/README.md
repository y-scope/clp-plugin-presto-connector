# Packaging

Builds installable `.deb`, `.rpm`, and `.tar.gz` artifacts of the CLP Presto
connector. Each artifact bundles both halves of the integration — the Java
coordinator JAR (`presto-connector/`) and the C++ Velox worker plugin
(`velox-connector/`) with its transitive runtime libraries — so a single
artifact installs everything needed.

Built on `manylinux_2_28` (glibc ≥ 2.28). The same artifacts work on
Debian 11+, Ubuntu 20.04+, RHEL 8+, AlmaLinux 8+, Rocky 8+, Fedora 29+, and
other glibc-based distros.

## Architecture

The plugin build needs Velox's C++ dependencies (Folly, fbthrift, Arrow,
fizz, wangle, mvfst, etc.), JDK 17, and packaging tools. To keep day-to-day
builds fast, we publish a **dependency image** — a `manylinux_2_28`-based
container with all of this pre-installed and tagged with the exact Velox SHA
that prestodb/presto's submodule pins.

`build.sh` assumes it's running inside that image. The image is published to
GHCR by CI and pulled by:

* **CI** (this repo's `build-packages.yaml`) — uses the GHA `container:`
  directive to run all steps inside the published image
* **Off-GitHub CI or local users** — use `build-dependency-image.sh`, which
  resolves the right image (local cache → upstream GHCR → build from scratch)
  and prints the image reference

## Local usage

```bash
./tools/build-packages/package.sh
```

Packages land in `./packages/` by default; override with `--output DIR`.
On first run (or after a velox pin bump), `package.sh` builds the build-env
image locally if the upstream pre-built image isn't available (~2 hours);
subsequent runs reuse the cached image.

`package.sh` is a thin host-side wrapper: it initialises the
`tools/yscope-dev-utils` submodule on the host (so git doesn't trip on the
container-vs-host UID ownership mismatch), resolves the build-env image
via `build-dependency-image.sh`, and runs `build.sh` inside it. All script
args are forwarded to `build.sh` — see `build.sh --help`.

### `build-dependency-image.sh`

Resolution order:

1. **Local Docker cache** — `docker image inspect`
2. **Upstream GHCR** — anonymous pull of `ghcr.io/y-scope/clp-plugin-presto-connector/build-env:velox-<sha>`
3. **Build from scratch** — `docker buildx build` using
   `dependency-image/Dockerfile`, which curls velox's setup scripts at the
   pinned SHA from `raw.githubusercontent.com` inside the image (~2 hours)

Override the upstream registry with `UPSTREAM_IMAGE_REPO=...` if you mirror
the image internally.

## Prerequisites

For `package.sh` (the local entry point):

* **Docker** with buildx
* **curl** and **python3** — needed only when the build-env image must be
  built locally (first run / velox pin bump / upstream unavailable)
* **~10 GB free disk** (one-time, for the image)
* **~16 GB memory** if building the image locally (Folly link peaks near 16 GB)

`build.sh` itself runs inside the build-env image — it carries all
build-time tools. Submodules are initialised on the host by `package.sh`
(or, in CI, by the `actions/checkout` step) before the container launches,
not by `build.sh`.

## Outputs

```
clp-plugin-presto-connector_<version>-1_<arch>.deb
clp-plugin-presto-connector-<version>-1.<rpm-arch>.rpm
clp-plugin-presto-connector-<version>-linux-<arch>.tar.gz
```

All three carry the same content. The `.deb` and `.rpm` install at fixed
paths the Presto worker expects; the `.tar.gz` ships the same files under
a portable wrapper dir for consumers to relocate.

Default install layout (`.deb` / `.rpm`):

```
/opt/clp-plugin-presto-connector/
├── coordinator/
│   └── clp-plugin-presto-connector.jar
└── worker/
    ├── libclp-plugin-velox-connector.so
    └── lib/                               # bundled non-system .so deps
```

The `.tar.gz` wraps `coordinator/` and `worker/` under
`clp-plugin-presto-connector-<version>-linux-<arch>/`. To install at the
default `.deb`/`.rpm` paths:

```bash
tar xzf <archive>
cp -a clp-plugin-presto-connector-*-linux-*/. /opt/clp-plugin-presto-connector/
```

## CI parity

CI (`.github/workflows/build-packages.yaml`) ensures the dependency image
via `build-dependency-image.yaml`, then runs `build.sh` inside it via GHA's
`container:` directive. Local users go through `package.sh`, which resolves
the image differently but invokes the same `build.sh`. Package-build logic
is shared.

## Troubleshooting

* **`ERROR: this script must run inside the clp-plugin-presto-connector
  build-env image`** — `build.sh` was invoked outside the image. See
  [Local usage](#local-usage).
* **`Cannot connect to the Docker daemon`** — start Docker (Docker Desktop
  on macOS/Windows, `systemctl start docker` on Linux).
* **Out of disk** — the build-env image is ~5 GB; intermediate state under
  `build/` and `velox-connector/build/` adds another few GB.
  `docker system prune -a` and `rm -rf build velox-connector/build` reclaim
  space.

---

The sections below are reference material for anyone modifying the build.

## Dependency image

Built from `tools/build-packages/dependency-image/Dockerfile`:

* **Base** — `quay.io/pypa/manylinux_2_28:latest` (glibc 2.28 ABI floor).
* **Velox deps** — installed by Velox's own `setup-manylinux.sh` (sourced
  from the cloned Velox tree at the pinned SHA). This builds Folly, fbthrift,
  Arrow, Boost, fizz, wangle, mvfst, glog, gflags, fmt, snappy, protobuf,
  duckdb, stemmer, thrift, etc., into `/usr/local`.
* **JDK 17** — `dnf install java-17-openjdk-devel` (for `mvnw`).
* **Packaging tools** — `dpkg`, `gettext` (`envsubst`), `patchelf`,
  `rpm-build`.
* **go-task** — pinned binary from GitHub releases, installed to
  `/opt/go-task/bin`.

Published as `ghcr.io/<repo>/build-env:velox-<velox_sha>`. The tag tracks
the velox SHA pinned by `prestodb/presto`'s submodule at the presto commit
that `velox-connector/CMakeLists.txt` references via
`set(PRESTO_GIT_TAG ...)` — guaranteeing header/ABI compatibility between
the image's prebuilt deps and what the plugin links against at build time.

### Rebuild policy

`build-dependency-image.yaml` rebuilds when **either**:

* the image doesn't yet exist in GHCR (e.g. velox pin bumped), or
* `tools/build-packages/dependency-image/**` changed in this push.

The tag stays the same across Dockerfile changes — the image is mutable at
its tag. Trade-off is intentional: a Dockerfile change is rare enough that
versioning the tag isn't worth the complexity, and the *plugin packages*
are the durable artifacts, not this build env.

### Shared helpers (`lib.sh`)

`dependency-image/lib.sh` is sourced by both `build-dependency-image.sh`
and the workflow, exposing:

* `derive_velox_sha` — resolves the velox SHA from
  `velox-connector/CMakeLists.txt`'s `PRESTO_GIT_TAG` via two HTTP calls
  to GitHub's contents API. Echoes the SHA on stdout. Honours
  `GITHUB_TOKEN` (raises the anon-API rate limit).
* `build_image <tag> <platform> <velox-sha> <--push|--load>` — runs
  `docker buildx build` with our Dockerfile, passing `VELOX_SHA` as a
  build arg. The Dockerfile curls velox's `setup-*.sh` scripts at that
  SHA from `raw.githubusercontent.com`.

## Build flow

```
build.sh (inside build-env image)
  ├── init submodules
  ├── task velox-connector:build
  │     ├── install plugin C++ deps (log-surgeon, ystdlib, fmt, ...)
  │     ├── cmake configure (FetchContents prestodb/presto + CLP)
  │     └── cmake --build → velox-connector .so
  ├── mvnw help:evaluate (from fetched presto tree) → derive version
  ├── mvnw package (from fetched presto tree) → presto-connector .jar
  ├── stage payload at /opt/clp-plugin-presto-connector/...
  ├── ldd walk → bundle non-system .so deps → patchelf RUNPATHs
  ├── strip bundled libs (plugin .so left unstripped) + chmod 0644
  └── dpkg-deb / rpmbuild / tar → output_dir
```

## Packaging mechanics

`build.sh` stages the install tree once, then emits all three package
formats from that single tree. The `.deb` and `.rpm` use the install paths
in [Outputs](#outputs) as the contract with the Presto worker that loads
them; they're set as readonly constants near the top of `build.sh`
(`PRESTO_JAR_DIR`, `VELOX_SO_DIR`) and threaded into:

* `rpmbuild` via `--define presto_jar_dir=... --define velox_so_dir=...`,
  which the `.spec` references as `%{presto_jar_dir}` / `%{velox_so_dir}`.
* The `.deb` staging tree directly — paths are baked into the staged
  directory structure; no template substitution needed.

The `.tar.gz` is the portable artifact and ships a canonical `coordinator/`
+ `worker/` layout under its top-level wrapper dir, decoupled from
`PRESTO_JAR_DIR` / `VELOX_SO_DIR`. Consumers extract and place those
subdirs wherever their distro expects.

Before any format-specific emit step, the staged files are normalized:

* `strip --strip-unneeded` on the bundled vendored `.so`s only (folly,
  glog, boost, antlr4-runtime, ...). The plugin `.so` is left unstripped
  so crash backtraces resolve to our source.
* `chmod 0644` on the JAR, main `.so`, and every bundled lib (`cp` may
  preserve overly-permissive source modes).

### `.deb`

`package-specs/deb/clp-plugin-presto-connector.control.in` is a Debian control-file
template with `$deb_version` and `$PKG_ARCH` placeholders. `envsubst` fills
them in to produce `DEBIAN/control`; the staged tree is then handed to
`dpkg-deb --build --root-owner-group`, where the flag records all files as
`root:root` regardless of who ran the build.

### `.rpm`

`package-specs/rpm/clp-plugin-presto-connector.spec` is a short spec file with no
`%build` step (the binaries already exist by the time `rpmbuild` runs).
`%install` `cp -a`s the staged payload into `%{buildroot}`, and `%files`
captures it. The invocation:

* `--target ${rpm_arch}` — sets the package arch (`x86_64` / `aarch64`)
  without needing a `BuildArch:` directive in the spec.
* `--define` macros for `pkg_version`, `pkg_release`, `payload_dir`,
  `presto_jar_dir`, `velox_so_dir` — all per-build values stay out of the
  spec file.
* `--bb` — binary build only (no source RPM).

Two notable spec choices:

* `AutoReqProv: no` plus explicit `Requires: glibc >= 2.28`, `libstdc++` —
  rpm's auto-scanner would otherwise pin every soname embedded in the
  bundled `.so`s, defeating the bundling strategy.
* `%files` owns the leaf install dirs (`%dir %{presto_jar_dir}` /
  `%dir %{velox_so_dir}` / `%dir %{velox_so_dir}/lib`); the
  `/opt/clp-plugin-presto-connector/` top dir is created implicitly at
  install time.

### `.tar.gz`

`tar -C ${staging} --owner=0 --group=0 --numeric-owner -czf ${tar_file}
${tar_dirname}`. The ownership flags normalize all entries to UID/GID 0 so
the tarball is reproducible across build hosts; without them, the
building user's UID/GID would be baked into every entry.

## Shared-library bundling

The plugin `.so` is built with hidden visibility and no `-z defs`, so it
carries no link-time soname dependency on Folly/Arrow/fbthrift/etc. —
those symbols resolve at `dlopen()` time from the host Presto worker. The
runtime libraries still need to ship with the package: `build.sh` walks
`ldd` output, copies every non-system dependency into
`<velox_so_dir>/lib/`, and rewrites RUNPATHs with `patchelf`:

* Each bundled `.so` gets `$ORIGIN` prepended to its existing RUNPATH
  (preserve-and-prepend — any build-time path the lib relied on for
  `dlopen()` stays intact).
* The main plugin `.so` gets `$ORIGIN/lib` prepended to its existing
  RUNPATH (same shape: keep any plugin-loader paths the build-time
  RUNPATH may carry).

System libraries (libc, libstdc++, libgcc_s, libm, libdl, libpthread, ld
loader, ...) are not bundled; they come from the target distro's glibc.

### Why bundle?

The supported distro range spans two actively-maintained OpenSSL generations
that are ABI-incompatible — a binary linked against `libssl.so.1.1` won't
find `libssl.so.3` on a newer system, and vice versa:

| Distro | OpenSSL | ICU |
|---|---|---|
| RHEL 8, AlmaLinux 8, Rocky 8, Ubuntu 20.04, Debian 11 | 1.1 | 60 |
| RHEL 9, AlmaLinux 9, Rocky 9, Ubuntu 22.04+, Debian 12+ | 3.0 | 70+ |

Bundling ships the exact library versions the binary was built against, so
a single artifact runs across the whole supported range without per-distro
rebuilds or compat packages. The ABI floor is glibc 2.28 (from the
`manylinux_2_28` base); everything above it — OpenSSL, ICU, libcurl and
their transitive deps — is bundled. The mechanism follows Python's manylinux
playbook.

### Inspecting the bundle

```bash
dpkg-deb --contents packages/clp-plugin-presto-connector_*_<arch>.deb \
    | awk '/\/opt\/clp-plugin-presto-connector\/worker\/lib\//{print $NF}'
# or, for the .rpm:
rpm -qlp packages/clp-plugin-presto-connector-*.<rpm-arch>.rpm \
    | grep /opt/clp-plugin-presto-connector/worker/lib/
```

## SNAPSHOT versions

`presto-connector/pom.xml` carries a Maven-style `0.1.0-SNAPSHOT`; the
build rewrites the `-` to `~` for the `.deb`/`.rpm` `Version:` field,
producing `0.1.0~SNAPSHOT` in package filenames. Both dpkg and rpm sort
`~` before end-of-string (Debian Policy §5.6.12; rpm follows the same
convention), so the pre-release correctly sorts before the eventual
`0.1.0` release. rpm's `Version:` field also forbids `-` outright.
