# Packaging

This directory builds installable `.deb`, `.rpm`, and `.tar.gz` artifacts for the CLP Presto connector. Each artifact contains both plugin components:

* Java coordinator plugin from `presto-connector/`
* C++ Velox worker plugin from `velox-connector/`, plus its non-system runtime libraries

The artifacts are built on `manylinux_2_28` (glibc 2.28) and target common Linux distributions with glibc 2.28 or newer, including Debian 11+, Ubuntu 20.04+, RHEL/AlmaLinux/Rocky Linux 8+, and Fedora 29+.

## Build model

The package build needs Velox C++ dependencies, JDK 17, go-task, and packaging tools. CI provides these through a hash-tagged build-env image based on `manylinux_2_28`.

`internal/container/build-artifacts.sh` runs inside the build-env image, builds both connector components once, stages a shared payload, and emits all three package formats.

## Outputs

The workflow emits one artifact of each format per architecture:

```text
clp-plugin-presto-connector_<package-version>-1_<arch>.deb
clp-plugin-presto-connector-<package-version>-1.<rpm-arch>.rpm
clp-plugin-presto-connector-<maven-version>-linux-<arch>.tar.gz
```

The `.deb` and `.rpm` install under `/opt/clp-plugin-presto-connector/`, with the coordinator JAR under `coordinator/` and the Velox plugin plus its bundled non-system libraries under `worker/`. The tarball contains the same two directories beneath a relocatable top-level directory.

## CI flow

`.github/workflows/build-packages.yaml`:

1. resolves the package version from the workflow input or `presto-connector/pom.xml`
2. ensures the hash-tagged build-env image exists through `.github/workflows/build-dependency-image.yaml`
3. runs `internal/container/build-artifacts.sh` for `amd64` and `arm64`
4. uploads the `.deb`, `.rpm`, and `.tar.gz` artifacts using their generated filenames

## Package construction

The container-side builder:

1. builds `libclp-plugin-velox-connector.so` using the dependencies already installed in the build-env image
2. builds `clp-plugin-presto-connector.jar` using the fetched Presto Maven wrapper
3. copies non-system shared-library dependencies beside the worker plugin and configures relative RUNPATHs
4. normalizes file modes and ownership
5. emits Debian, RPM, and relocatable tar packages from the shared payload

Package versions must begin with a digit and otherwise use letters, digits, `.`, `+`, `~`, or `-`. Because RPM forbids `-` in its `Version` field, Debian and RPM versions replace `-` with `~`; tarball filenames preserve the original Maven version.
