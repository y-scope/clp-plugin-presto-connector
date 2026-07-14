#!/usr/bin/env bash

# Build the Java coordinator and C++ worker plugins, assemble one install tree,
# and emit the same files as .deb, .rpm, and relocatable .tar.gz artifacts.
#
# CI runs this container-side implementation inside the build-env image. See
# tools/build-packages/README.md for the overall packaging flow.

set -o errexit
set -o nounset
set -o pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." &>/dev/null && pwd)"

# Destination paths used by .deb and .rpm. Environment overrides support a
# non-default install layout; the tarball remains relocatable.
readonly PLUGIN_ROOT="${PLUGIN_ROOT:-/opt/clp-plugin-presto-connector}"
readonly PRESTO_JAR_DIR="${PRESTO_JAR_DIR:-${PLUGIN_ROOT}/coordinator}"
readonly VELOX_SO_DIR="${VELOX_SO_DIR:-${PLUGIN_ROOT}/worker}"

# ── Helpers ───────────────────────────────────────────────────────────────────

show_help() {
    cat <<'EOF'
Usage: ./tools/build-packages/internal/container/build-artifacts.sh [OPTIONS]

Builds .deb / .rpm / .tar.gz packages for the current architecture. Must run
inside the build-env image.

Options:
  --output DIR   Output directory for built packages (default: ./packages)
  --version VER  Override package version
                 (default: derived from presto-connector/pom.xml)
                 VER must start with a digit and use [0-9A-Za-z.+~-]
  --help         Show this help

See tools/build-packages/README.md for CI usage and package-build details.
EOF
}

die() {
    echo >&2 "ERROR: $*"
    exit 1
}

require_value() {
    [[ -n "${2:-}" ]] || die "$1 requires a value"
}

validate_package_version() {
    local candidate="$1"
    [[ "${candidate}" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] \
        || die "invalid package version '${candidate}'; expected a digit followed by letters, digits, '.', '+', '~', or '-'"
}

# ── Parse arguments ───────────────────────────────────────────────────────────

output_dir="${src}/packages"
version=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --output)  require_value "$1" "${2:-}"; output_dir="$2"; shift 2 ;;
        --version) require_value "$1" "${2:-}"; version="$2";    shift 2 ;;
        --help)    show_help; exit 0 ;;
        *) die "unknown option: $1 (use --help for usage)" ;;
    esac
done

[[ -z "${version}" ]] || validate_package_version "${version}"

# ── Locate Java for Maven ─────────────────────────────────────────────────────

# Give Maven an explicit JDK location when the caller did not provide one.
if [[ -z "${JAVA_HOME:-}" ]]; then
    javac_path=$(readlink -f "$(command -v javac)")
    export JAVA_HOME="${javac_path%/bin/javac}"
fi

# ── Resolve architecture ──────────────────────────────────────────────────────

# Debian and tarball names use amd64/arm64; RPM uses x86_64/aarch64.
case "$(uname -m)" in
    x86_64)  arch="amd64"; rpm_arch="x86_64"  ;;
    aarch64) arch="arm64"; rpm_arch="aarch64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

pkg_specs_dir="${src}/tools/build-packages/package-specs"
project_build_dir="${CLP_PLUGIN_BUILD_DIR:-${src}/build}"
velox_build_dir="${project_build_dir}/velox-connector"
build_root="${src}/build/packaging"
payload="${build_root}/payload"
artifacts=()

mkdir -p "${output_dir}"
output_dir="$(cd "${output_dir}" && pwd)"
# build_root is recreated below, so final output must live outside it.
if [[ "${output_dir}" == "${build_root}" || "${output_dir}" == "${build_root}/"* ]]; then
    die "--output must not be ${build_root} or one of its subdirectories"
fi

# Recreate staging so files left by an earlier build cannot enter new packages.
rm -rf "${build_root}"
mkdir -p "${build_root}"

# ── Build the C++ worker plugin ───────────────────────────────────────────────

# The caller initializes submodules. Reuse the dependency installations and
# CMake settings already in the build-env image instead of rebuilding them.
echo "==> Building velox-connector .so with image-installed dependencies..."
task --concurrency 1 -d "${src}" velox-connector:build-with-installed-deps
so_file="${velox_build_dir}/libclp-plugin-velox-connector.so"
[[ -f "${so_file}" ]] || die "expected .so not found at ${so_file}"
echo "    -> ${so_file}"

# ── Choose the package version ────────────────────────────────────────────────

# The worker build fetches Presto, including its Maven wrapper. Reuse that
# wrapper to read this project's version and build its Java plugin.
presto_src="${velox_build_dir}/_deps/presto_native_execution-src"
maven_wrapper="${presto_src}/mvnw"
[[ -x "${maven_wrapper}" ]] \
    || die "expected Maven wrapper not found or not executable at ${maven_wrapper}"

run_maven() {
    MAVEN_PROJECTBASEDIR="${presto_src}" \
        "${maven_wrapper}" -f "${src}/presto-connector/pom.xml" "$@"
}

if [[ -z "${version}" ]]; then
    echo "==> Deriving version from presto-connector/pom.xml via mvnw..."
    version=$(run_maven \
        -q help:evaluate -Dexpression=project.version -DforceStdout) \
        || die "mvnw help:evaluate failed"
    [[ -n "${version}" ]] || die "derived project.version is empty"
fi

validate_package_version "${version}"

# Normalize `1.0-rc1` to `1.0~rc1`: RPM forbids `-` in Version, and both
# package managers sort `~` prereleases before the final release.
pkg_version_normalized="${version//-/\~}"

echo ""
echo "==> CLP Plugin Presto Connector package build"
echo "    Arch:    ${arch}"
echo "    Version: ${version}"
echo "    Output:  ${output_dir}"
echo ""

# ── Build the Java coordinator plugin ─────────────────────────────────────────

echo "==> Building presto-connector .jar via fetched mvnw..."
run_maven clean package -DskipTests -B

# Select the main plugin JAR, excluding optional source and documentation JARs.
jar_file=$(find "${src}/presto-connector/target" -maxdepth 1 \
    -name 'clp-plugin-presto-connector-*.jar' \
    ! -name '*-sources.jar' ! -name '*-javadoc.jar' \
    -print -quit)
[[ -f "${jar_file}" ]] \
    || die "expected .jar not found in presto-connector/target/"
echo "    -> ${jar_file}"

# ── Stage the shared package payload ──────────────────────────────────────────

# `payload` is the target filesystem tree used by .deb/.rpm and rerooted for
# the tarball. Build it once so every format contains the same files.

# Add a library search path without discarding existing paths. The Linux loader
# expands `$ORIGIN` to the directory containing the current shared library.
prepend_runpath() {
    local entry="$1"
    local file="$2"
    local old_runpath new_runpath="${entry}"

    old_runpath=$(patchelf --print-rpath "${file}" 2>/dev/null || true)
    if [[ "${old_runpath}" == "${entry}" || "${old_runpath}" == "${entry}:"* ]]; then
        new_runpath="${old_runpath}"
    elif [[ -n "${old_runpath}" ]]; then
        new_runpath+=":${old_runpath}"
    fi
    patchelf --set-rpath "${new_runpath}" "${file}"
}

bundle_velox_shared_libraries() {
    local installed_so="$1"
    # Keep bundled dependencies in worker/lib beside the installed plugin.
    local bundled_dir="${payload}${VELOX_SO_DIR}/lib"
    mkdir -p "${bundled_dir}"

    # `ldd` lists every library needed to load the plugin. Bundle third-party
    # entries so the payload does not rely on distro-specific OpenSSL/libcurl
    # versions. Leave core C/C++ runtimes and the loader to the target system;
    # build-container copies may be incompatible with its glibc.
    local system_libs=(
        linux-vdso libc libm libmvec libanl libutil libnsl
        libpthread libdl librt libresolv 'libstdc\+\+' libgcc_s
    )
    # Loader names include a platform component before `.so`, for example
    # `ld-linux-x86-64.so.2`, so match them separately. Musl entries are
    # defensive; published packages target glibc-based distributions.
    local ld_loaders=(ld-linux ld-musl 'libc\.musl')

    # Combine the names above into one "skip" pattern. It matches the complete
    # library name, including `.so` version numbers, so the loop below can leave
    # files such as `libc.so.6` and `ld-linux-x86-64.so.2` out of the package.
    # Here, `IFS='|'` puts `|` ("or") between the names. It applies only while
    # building this pattern, so the later `read` still splits `ldd` output on
    # whitespace.
    local skip_re
    skip_re=$(IFS='|'; echo "^((${system_libs[*]})|(${ld_loaders[*]})-[^.]+)\.so(\.[0-9]+)*$")

    local ldd_out
    ldd_out=$(LC_ALL=C ldd "${installed_so}" 2>&1) || {
        echo >&2 "ERROR: ldd failed for ${installed_so}:"
        echo >&2 "${ldd_out}"
        exit 1
    }

    echo "==> Bundling velox-connector shared library dependencies..."
    # Copy resolved `<name> => <path>` entries, collect `not found` errors, and
    # ignore loader metadata without `=>`.
    local soname op target _rest missing=()
    while read -r soname op target _rest; do
        case "${op}${target}" in
            "=>not")  missing+=("${soname}"); continue ;;
            "=>"/*)   ;;
            *)        continue ;;
        esac
        [[ "${soname}" =~ ${skip_re} ]] && continue
        [[ -f "${bundled_dir}/${soname}" ]] && continue
        cp --dereference "${target}" "${bundled_dir}/${soname}"
        echo "    Bundled: ${soname}"
    done <<< "${ldd_out}"

    if (( ${#missing[@]} > 0 )); then
        echo >&2 "ERROR: unresolved shared library deps for ${installed_so}:"
        printf >&2 '  %s\n' "${missing[@]}"
        exit 1
    fi

    echo "==> Patching velox-connector RUNPATHs..."
    # Package-relative paths keep working after installation or relocation;
    # preserve existing RUNPATH entries as fallbacks. Bundled libraries look
    # for their dependencies in the same lib/ directory.
    for lib in "${bundled_dir}"/*.so*; do
        [[ -f "${lib}" ]] || continue
        prepend_runpath '$ORIGIN' "${lib}"
    done
    # The plugin looks in the adjacent lib/ directory.
    prepend_runpath '$ORIGIN/lib' "${installed_so}"
}

echo "==> Staging payload..."
presto_jar_install="${payload}${PRESTO_JAR_DIR}"
velox_so_install="${payload}${VELOX_SO_DIR}"
mkdir -p "${presto_jar_install}" "${velox_so_install}"

cp "${jar_file}" "${presto_jar_install}/clp-plugin-presto-connector.jar"
cp "${so_file}" "${velox_so_install}/libclp-plugin-velox-connector.so"

bundle_velox_shared_libraries "${velox_so_install}/libclp-plugin-velox-connector.so"

# Strip unneeded symbols from bundled libraries to reduce package size. Keep
# the plugin unstripped so crash backtraces retain useful symbol names.
find "${velox_so_install}/lib" -type f -name '*.so*' \
    -exec strip --strip-unneeded {} +

# Normalize source modes. JARs and shared libraries are loaded rather than
# executed directly, so install them as non-executable 0644 files.
chmod 0644 \
    "${presto_jar_install}/clp-plugin-presto-connector.jar" \
    "${velox_so_install}/libclp-plugin-velox-connector.so"
find "${velox_so_install}/lib" -type f -exec chmod 0644 {} +

# ── Build package formats ─────────────────────────────────────────────────────

# Reuse the staged files for all formats: .deb for Debian-based systems, .rpm
# for RPM-based distributions, and .tar.gz for manual extraction.

build_deb() {
    local staging="${build_root}/staging-deb"
    local deb_file="${build_root}/clp-plugin-presto-connector_${pkg_version_normalized}-1_${arch}.deb"

    # A .deb is a filesystem tree plus metadata in DEBIAN/control. Copy the
    # shared payload, then render this build's version and architecture.
    rm -rf "${staging}"
    cp -a "${payload}" "${staging}"
    mkdir -p "${staging}/DEBIAN"
    PKG_ARCH="${arch}" deb_version="${deb_version}" \
        envsubst '$deb_version $PKG_ARCH' \
        < "${pkg_specs_dir}/deb/clp-plugin-presto-connector.control.in" \
        > "${staging}/DEBIAN/control"

    echo "==> Building .deb..."
    # Record installed files as root-owned, independent of the container user.
    dpkg-deb --build --root-owner-group "${staging}" "${deb_file}"
    artifacts+=("${deb_file}")
    echo "    -> ${deb_file}"
}

build_rpm() {
    local rpm_version="${pkg_version_normalized}"
    local rpmbuild_dir="${build_root}/rpmbuild"
    local rpm_filename="clp-plugin-presto-connector-${rpm_version}-1.${rpm_arch}.rpm"
    local rpm_file_out="${build_root}/${rpm_filename}"

    rm -rf "${rpmbuild_dir}"
    # An RPM spec defines metadata and install rules for the prebuilt payload.
    # Create its input/output directories; rpmbuild creates the rest.
    mkdir -p "${rpmbuild_dir}"/{SPECS,RPMS}
    cp "${pkg_specs_dir}/rpm/clp-plugin-presto-connector.spec" \
       "${rpmbuild_dir}/SPECS/clp-plugin-presto-connector.spec"

    echo "==> Building .rpm..."
    # Pass the payload and build settings into the spec as macros. `--bb` emits
    # the installable binary RPM without a source RPM.
    rpmbuild \
        --define "_topdir ${rpmbuild_dir}" \
        --define "pkg_version ${rpm_version}" \
        --define "pkg_release 1" \
        --define "payload_dir ${payload}" \
        --define "plugin_root ${PLUGIN_ROOT}" \
        --define "presto_jar_dir ${PRESTO_JAR_DIR}" \
        --define "velox_so_dir ${VELOX_SO_DIR}" \
        --target "${rpm_arch}" \
        --bb "${rpmbuild_dir}/SPECS/clp-plugin-presto-connector.spec"

    cp "${rpmbuild_dir}/RPMS/${rpm_arch}/${rpm_filename}" "${rpm_file_out}"
    artifacts+=("${rpm_file_out}")
    echo "    -> ${rpm_file_out}"
}

build_tarball() {
    local tar_dirname="clp-plugin-presto-connector-${version}-linux-${arch}"
    local staging="${build_root}/staging-tar"
    local tar_file="${build_root}/${tar_dirname}.tar.gz"
    local tar_root="${staging}/${tar_dirname}"

    # The tarball is manually extracted rather than installed by a package
    # manager. Reroot the payload under coordinator/worker instead of retaining
    # the system-package install paths.
    rm -rf "${staging}"
    mkdir -p "${tar_root}/coordinator" "${tar_root}/worker"
    cp -a "${payload}${PRESTO_JAR_DIR}/." "${tar_root}/coordinator/"
    cp -a "${payload}${VELOX_SO_DIR}/."   "${tar_root}/worker/"

    echo "==> Building .tar.gz..."
    # Normalize ownership instead of embedding the container user's IDs.
    tar -C "${staging}" --owner=0 --group=0 --numeric-owner \
        -czf "${tar_file}" "${tar_dirname}"
    artifacts+=("${tar_file}")
    echo "    -> ${tar_file}"
}

build_deb
build_rpm
build_tarball

# ── Collect completed packages ────────────────────────────────────────────────

# Keep intermediate staging under build_root; copy only completed packages to
# the requested output directory.
echo ""
echo "==> Copying artifacts to ${output_dir}..."
cp "${artifacts[@]}" "${output_dir}/"

output_artifacts=()
for artifact in "${artifacts[@]}"; do
    output_artifacts+=("${output_dir}/${artifact##*/}")
done

echo ""
echo "========================================"
echo "Build complete"
echo "========================================"
ls -lh "${output_artifacts[@]}"
