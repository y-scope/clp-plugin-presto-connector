# Packaging

This directory builds installable `.deb`, `.rpm`, and `.tar.gz` artifacts for the CLP Presto connector. Each artifact contains both plugin components:

* Java coordinator plugin from `presto-connector/`
* C++ Velox worker plugin from `velox-connector/`, plus its non-system runtime libraries

The artifacts are built on `manylinux_2_28` (glibc 2.28) and target common Linux distributions with glibc 2.28 or newer, including Debian 11+, Ubuntu 20.04+, RHEL/AlmaLinux/Rocky Linux 8+, and Fedora 29+.

## Build model

The package build needs Velox C++ dependencies, JDK 17, go-task, and packaging tools. CI provides these through a hash-tagged **build-env image** based on `manylinux_2_28`.

The image is tagged as `env-<hash>`. The hash covers the dependency-image directory and context filtering, taskfiles, and `tools/yscope-dev-utils`, including relevant uncommitted inputs and executable modes. The tag identifies those source and configuration inputs; it is not a digest of upstream images because the base image currently uses the mutable `manylinux_2_28:latest` tag.

`internal/container/build-artifacts.sh` runs inside the build-env image and performs the actual package build. Local users should run `build-packages.sh`, which resolves the image and invokes the container-side script.

## Local usage

```bash
./tools/build-packages/build-packages.sh
```

Packages are written to `./packages/` by default. Use `--output DIR` to choose a different output directory, and `--version VER` to override the package version. When no version is provided, `internal/container/build-artifacts.sh` derives the Maven project version from `presto-connector/pom.xml`. Versions must start with a digit and otherwise contain only letters, digits, `.`, `+`, `~`, or `-`.

On the first run after a build-env input changes, `build-packages.sh` builds the image locally if it is not already available in Docker or in this repository's GHCR package. Later runs reuse the cached image.

Local builds use `.cache/maven/` for the Maven Wrapper distribution and downloaded artifacts, and `.cache/ccache/` for content-addressed C++ compilation results, with ccache capped at 1 GiB. These caches are shared across build-env revisions. FetchContent uses `.cache/fetchcontent/<hash>/` so Presto/Velox and CLP source and build trees remain isolated by build-env revision. See the [build-cache helper documentation](internal/build-cache/README.md) for the cache layout and integration API.

The top-level CMake build tree is ephemeral, while Task-installed C/C++ dependencies are read directly from the build-env image. The package build runs as root inside the container, so cache and intermediate build files may be root-owned on the host. The container writes final artifacts into an isolated staging directory, and the host process copies them into the requested output directory so they use the invoking user's UID/GID. The repository ignores `.cache/`; remove that directory when no package build is running to discard local cache state.

`build-packages.sh` also initializes submodules on the host before launching Docker. All arguments are forwarded to the container-side build; run `./tools/build-packages/build-packages.sh --help` for the supported options.

### Container privileges and file ownership

The package build container runs as root so it can use the root-owned dependencies installed in the image. The requested host output directory is not mounted into the container; the host process copies completed packages out of temporary staging.

### Build-env image resolution

`build-dependency-image.sh` resolves the image in this order:

1. local Docker cache (`docker image inspect`)
2. this repository's GHCR package (`docker pull ghcr.io/<owner>/<repo>/build-env:env-<hash>`)
3. local image build from `dependency-image/Dockerfile`

## Prerequisites

For local Linux and macOS builds through `build-packages.sh`:

* Docker with buildx, usable by the invoking user without `sudo`
* git and either `sha256sum` or `shasum`
* about 10 GB of free disk for the build-env image
* roughly 1 GiB of memory per available processor for a clean local image build

`internal/container/build-artifacts.sh` runs inside the build-env image, which provides all required build-time tools. Submodules are initialized before it starts: by `build-packages.sh` on the host for local builds, and by `actions/checkout` inside the job container in CI.

## Outputs

By default, artifacts are written under `./packages/`:

```text
./packages/clp-plugin-presto-connector_<package-version>-1_<arch>.deb
./packages/clp-plugin-presto-connector-<package-version>-1.<rpm-arch>.rpm
./packages/clp-plugin-presto-connector-<maven-version>-linux-<arch>.tar.gz
```

`<package-version>` is the Maven version after package naming normalization. `<maven-version>` is the original Maven version. All formats contain the same plugin files. The `.deb` and `.rpm` install to the standard plugin path:

```text
/opt/clp-plugin-presto-connector/
├── coordinator/
│   └── clp-plugin-presto-connector.jar
└── worker/
    ├── libclp-plugin-velox-connector.so
    └── lib/                               # bundled non-system .so deps
```

The `.tar.gz` contains the same `coordinator/` and `worker/` directories under a relocatable top-level directory:

```text
clp-plugin-presto-connector-<maven-version>-linux-<arch>/
├── coordinator/
└── worker/
```

To install the tarball, extract it and copy the payload into your chosen plugin directory:

```bash
tar xzf <archive>
cp -a clp-plugin-presto-connector-*-linux-*/<coordinator|worker>. /<plugin-directory>/clp-plugin-presto-connector/
```

## CI flow

`.github/workflows/build-packages.yaml` runs the same package build in CI:

1. resolve the package version from the workflow input or `presto-connector/pom.xml`
2. ensure the hash-tagged build-env image exists through `.github/workflows/build-dependency-image.yaml`
3. run `internal/container/build-artifacts.sh` inside that image for `amd64` and `arm64`
4. upload `.deb`, `.rpm`, and `.tar.gz` artifacts for each architecture

Local and CI package builds share `internal/container/build-artifacts.sh`. Local builds use `build-packages.sh` to resolve the image, initialize submodules, copy final artifacts into the host output directory, and configure persistent caches under `.cache/`. GitHub Actions invokes the container-side script directly inside its build-env job container.

## Troubleshooting

* **`Installed dependency settings not found`** — the container-side build was invoked without the dependencies supplied by the build-env image. Run `build-packages.sh` for a local package build.
* **`Cannot connect to the Docker daemon`** — start Docker, then rerun `build-packages.sh`.
* **Intermediate files are not writable outside the container** — local package builds run as root, so `.cache/`, `build/`, and `presto-connector/target/` may contain root-owned files. Remove them through a root container or repair their ownership before switching to a native host build. Final files under `packages/` are owned by the invoking user.
* **Out of disk** — the build-env image is about 5 GB, and intermediate build directories add several more GB. `docker system prune -a` and `rm -rf .cache build` reclaim most local build state.

---

The remaining sections are reference material for maintainers.

## Build-env image

The dependency image is built from `tools/build-packages/dependency-image/Dockerfile`:

* **Base image** — `quay.io/pypa/manylinux_2_28:latest`
* **Connector C/C++ dependencies** — installed by `task velox-connector:deps:install-all` under the image build directory
* **JDK 17** — `java-17-openjdk-devel`, required by Maven builds
* **Packaging tools** — `dpkg`, `gettext` (`envsubst`), `patchelf`, and `rpm-build`
* **go-task** — pinned release binary installed under `/opt/go-task/bin`

The published image reference is `ghcr.io/<repo>/build-env:env-<hash>`. When a hash input changes, CI computes a new tag and builds the image if that tag is not already present in GHCR.

### Host-side internals

Host-only support code is split by responsibility:

* `internal/build-cache/host.sh` prepares persistent cache directories, while `internal/build-cache/container.sh` configures build tools to consume them.
* `dependency-image/utils.sh` derives the build-env hash, formats its image reference, and drives `docker buildx` for the image resolver and dependency-image workflow.

## Package build flow

```text
internal/container/build-artifacts.sh (inside build-env image)
  ├── task velox-connector:build-with-installed-deps
  │     ├── use C++ deps and all-deps.cmake installed in the build-env image
  │     ├── configure with CMake (FetchContent: prestodb/presto + CLP)
  │     └── build libclp-plugin-velox-connector.so
  ├── resolve package version from --version or Maven project metadata
  ├── mvnw package → build clp-plugin-presto-connector.jar
  ├── stage payload under /opt/clp-plugin-presto-connector/...
  ├── ldd walk → copy non-system .so deps → patch RUNPATHs
  ├── strip bundled third-party libraries and normalize file modes
  └── emit .deb, .rpm, and .tar.gz artifacts
```

`internal/container/build-artifacts.sh` stages the install tree once, then emits all three package formats from that tree. `PRESTO_JAR_DIR` and `VELOX_SO_DIR`, defined near the top of the script, control the `.deb`/`.rpm` install paths and are passed into `rpmbuild` as spec macros. The `.tar.gz` remains relocatable and always uses a `coordinator/` plus `worker/` layout under its top-level directory.

Before any package is emitted, staged files are normalized:

* bundled third-party `.so` files are stripped with `strip --strip-unneeded`
* the plugin `.so` is left unstripped so crash backtraces retain the available symbol information
* the JAR, plugin `.so`, and bundled libraries are set to mode `0644`

### `.deb`

`package-specs/deb/clp-plugin-presto-connector.control.in` is a Debian control file template. `envsubst` fills in `$deb_version` and `$PKG_ARCH`, then `dpkg-deb --build --root-owner-group` records files as `root:root` regardless of the user running the build.

### `.rpm`

`package-specs/rpm/clp-plugin-presto-connector.spec` builds only the binary package; the binaries already exist before `rpmbuild` runs. The invocation:

* uses `--target ${rpm_arch}` to set the package architecture
* passes all per-build values through `--define` macros
* uses `--bb` to skip source RPM creation

The spec disables automatic dependency generation with `AutoReqProv: no` and sets explicit requirements on `glibc >= 2.28` and `libstdc++`. This prevents RPM from adding requirements for every bundled shared-library soname.

### `.tar.gz`

`internal/container/build-artifacts.sh` creates tarballs with:

```bash
tar -C "${staging}" --owner=0 --group=0 --numeric-owner -czf "${tar_file}" "${tar_dirname}"
```

The ownership flags normalize all archived entries to UID/GID 0 across build hosts.

## Shared-library bundling

The plugin `.so` is built with hidden visibility and without `-z defs`, so it does not carry link-time soname dependencies on Folly, Arrow, fbthrift, and similar libraries. Those symbols resolve at `dlopen()` time from the Presto worker process.

The package still ships the runtime libraries the plugin needs. `internal/container/build-artifacts.sh` walks `ldd` output, copies each non-system dependency into `<velox_so_dir>/lib/`, and rewrites RUNPATHs with `patchelf`:

* bundled libraries get `$ORIGIN` prepended to their existing RUNPATH
* the main plugin `.so` gets `$ORIGIN/lib` prepended to its existing RUNPATH

Existing RUNPATH entries are preserved so any build-time plugin-loader paths remain available. System libraries such as `libc`, `libstdc++`, `libgcc_s`, `libm`, `libdl`, `libpthread`, and the dynamic loader are not bundled; they come from the target distribution.

### Why bundle?

The supported distribution range spans incompatible OpenSSL and ICU versions:

| Distro | OpenSSL | ICU |
|---|---|---|
| RHEL 8, AlmaLinux 8, Rocky Linux 8, Ubuntu 20.04, Debian 11 | 1.1 | 60 |
| RHEL 9, AlmaLinux 9, Rocky Linux 9, Ubuntu 22.04+, Debian 12+ | 3.0 | 70+ |

Bundling ships the exact library versions used at build time, so one artifact can run across the supported range without per-distribution rebuilds or compat packages. The ABI floor remains glibc 2.28 from the `manylinux_2_28` base; newer dependencies such as OpenSSL, ICU, and libcurl are bundled.

### Inspecting the bundle

```bash
dpkg-deb --contents packages/clp-plugin-presto-connector_*_<arch>.deb | awk '/\/opt\/clp-plugin-presto-connector\/worker\/lib\//{print $NF}'
rpm -qlp packages/clp-plugin-presto-connector-*.<rpm-arch>.rpm | grep /opt/clp-plugin-presto-connector/worker/lib/
```

## Package naming limitations

Package versions must start with a digit and otherwise use only letters, digits, `.`, `+`, `~`, or `-`, a common safe subset for Debian, RPM, and filenames. RPM forbids `-` in the `Version:` field, so `.deb` and `.rpm` metadata and filenames replace `-` with `~`; `0.1.0-SNAPSHOT` becomes `0.1.0~SNAPSHOT`. The tarball filename keeps the original Maven version. For snapshot-style versions, the `~` form also keeps the package ordered before the eventual release package.
