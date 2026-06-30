#!/usr/bin/env bash

# Builds clp-plugin-presto-connector .deb / .rpm / .tar.gz packages.
#
# Must run inside the dependency image. See tools/build-packages/README.md
# for setup. Run with --help for usage.

set -o errexit
set -o nounset
set -o pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"

# Install layout. Overridable via env; also exposed to rpmbuild via --define.
readonly PRESTO_JAR_DIR="${PRESTO_JAR_DIR:-/opt/clp-plugin-presto-connector/coordinator}"
readonly VELOX_SO_DIR="${VELOX_SO_DIR:-/opt/clp-plugin-presto-connector/worker}"

# ── Helpers ───────────────────────────────────────────────────────────────────

show_help() {
    cat <<'EOF'
Usage: ./tools/build-packages/build.sh [OPTIONS]

Builds .deb / .rpm / .tar.gz packages of the CLP Presto connector for the
host architecture. Must run inside the dependency image.

Options:
  --output DIR   Output directory for built packages (default: ./packages)
  --version VER  Override package version
                 (default: derived from presto-connector/pom.xml)
  --help         Show this help

See tools/build-packages/README.md for how to obtain and run inside the
dependency image.
EOF
}

require_value() {
    [[ -n "${2:-}" ]] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
}

# ── Parse arguments ───────────────────────────────────────────────────────────

output_dir="${src}/packages"
version=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --output)  require_value "$1" "${2:-}"; output_dir="$2"; shift 2 ;;
        --version) require_value "$1" "${2:-}"; version="$2";    shift 2 ;;
        --help)    show_help; exit 0 ;;
        *) echo "ERROR: Unknown option: $1" >&2; echo "Use --help for usage" >&2; exit 1 ;;
    esac
done

# ── Validate environment ──────────────────────────────────────────────────────

# Refuse to run outside the dependency image. The image sets this marker
# (see tools/build-packages/dependency-image/Dockerfile).
if [[ "${CLP_PLUGIN_BUILD_ENV:-}" != "1" ]]; then
    cat <<EOF >&2
ERROR: this script must run inside the clp-plugin-presto-connector
build-env image (CLP_PLUGIN_BUILD_ENV=1 not set).

See tools/build-packages/README.md for how to obtain the image and run
this script inside it.
EOF
    exit 1
fi

for cmd in task patchelf rpmbuild dpkg-deb tar javac envsubst git cmake; do
    command -v "${cmd}" &>/dev/null || {
        echo "ERROR: required command '${cmd}' not found in PATH" >&2
        exit 1
    }
done

case "$(uname -m)" in
    x86_64)  arch="amd64"; rpm_arch="x86_64"  ;;
    aarch64) arch="arm64"; rpm_arch="aarch64" ;;
    *) echo "ERROR: unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "${output_dir}"
output_dir="$(cd "${output_dir}" && pwd)"

pkg_specs_dir="${src}/tools/build-packages/package-specs"
build_root="${src}/build/packaging"
payload="${build_root}/payload"
# Start each run from a clean build_root so stale artifacts from prior runs
# (e.g. a previous --version) don't leak into the final cp glob below.
rm -rf "${build_root}"
mkdir -p "${build_root}"

# ── Build velox-connector .so ─────────────────────────────────────────────────

# Submodules are initialised by the caller on the host (package.sh, or GHA's
# checkout step with submodules: true) — not here. Running `git` against the
# bind-mounted source tree from inside the container trips git's "dubious
# ownership" check whenever the container UID (typically root) doesn't match
# the host UID that owns the files.

echo "==> Building velox-connector .so via task velox-connector:build..."
# The velox-connector taskfile (taskfiles/velox-connector/) installs the plugin's
# C++ deps (log-surgeon, ystdlib, antlr4-runtime, fmt, spdlog, ...) under
# build/velox-connector/deps/cpp/ and emits an `all-deps.cmake` that points
# find_package() at them. It then runs cmake configure (which FetchContents
# presto + CLP) and cmake --build for the plugin target. Idempotent: re-runs
# skip up-to-date deps.
task -d "${src}" velox-connector:build
so_file="${src}/build/velox-connector/libclp-plugin-velox-connector.so"
[[ -f "${so_file}" ]] || { echo "ERROR: expected .so not found at ${so_file}" >&2; exit 1; }
echo "    -> ${so_file}"

# ── Derive version ────────────────────────────────────────────────────────────

# mvnw is available now that the velox build FetchContented presto. Maven's
# own resolver is immune to pom.xml structural changes (e.g. a future
# `<parent><version>` block) that would silently mis-capture a regex.
presto_src="${src}/build/velox-connector/_deps/presto_native_execution-src"
if [[ -z "${version}" ]]; then
    echo "==> Deriving version from presto-connector/pom.xml via mvnw..."
    version=$(MAVEN_PROJECTBASEDIR="${presto_src}" \
        MAVEN_OPTS="-Duser.home=${HOME}" \
        "${presto_src}/mvnw" -f "${src}/presto-connector/pom.xml" \
        -q help:evaluate -Dexpression=project.version -DforceStdout) || {
        echo "ERROR: mvnw help:evaluate failed" >&2
        exit 1
    }
    [[ -n "${version}" ]] || {
        echo "ERROR: derived project.version is empty" >&2
        exit 1
    }
fi

# rpm Version: forbids '-'; Debian/rpm both sort '~' before end-of-string, so
# `-SNAPSHOT` becomes `~SNAPSHOT` and pre-releases sort before the eventual
# release. See README "SNAPSHOT versions".
pkg_version_normalized="${version//-/\~}"

echo ""
echo "==> CLP Plugin Presto Connector package build"
echo "    Arch:    ${arch}"
echo "    Version: ${version}"
echo "    Output:  ${output_dir}"
echo ""

# ── Build presto-connector .jar ───────────────────────────────────────────────

# Use mvnw fetched as a side-effect of the velox-connector cmake build (which
# FetchContents prestodb/presto for headers).
#
# user.home pin: GHA's container UID has no /etc/passwd entry, so Java's
# getpwuid_r returns "?" and Maven would otherwise write its local repo to
# `?/.m2/` in the cwd.
echo "==> Building presto-connector .jar via fetched mvnw..."
MAVEN_PROJECTBASEDIR="${presto_src}" \
MAVEN_OPTS="-Duser.home=${HOME}" \
    "${presto_src}/mvnw" -f "${src}/presto-connector/pom.xml" \
    clean package -DskipTests -B

jar_file=$(find "${src}/presto-connector/target" -maxdepth 1 \
    -name 'clp-plugin-presto-connector-*.jar' \
    ! -name '*-sources.jar' ! -name '*-javadoc.jar' \
    -print -quit)
[[ -f "${jar_file}" ]] || { echo "ERROR: expected .jar not found in presto-connector/target/" >&2; exit 1; }
echo "    -> ${jar_file}"

# ── Stage payload ─────────────────────────────────────────────────────────────

bundle_velox_shared_libraries() {
    local installed_so="$1"
    # Bundle subdir hardcoded to `lib`. Mirror to lib64 here if we ever pick up
    # a transitive dep whose own RUNPATH points at $ORIGIN/../lib64.
    local bundled_dir="${payload}${VELOX_SO_DIR}/lib"
    mkdir -p "${bundled_dir}"

    # System libs that come from the target distro at install time. Don't
    # bundle these — they must come from the host so the package works
    # across glibc/libstdc++ versions.
    local system_libs=(
        linux-vdso libc libm libmvec libanl libutil libnsl
        libpthread libdl librt libresolv 'libstdc\+\+' libgcc_s
    )
    # Dynamic loaders ship as ld-linux-<flavor>.so.<n> /
    # libc.musl-<flavor>.so.<n> — the `-[^.]+` in the regex below matches
    # the `-<flavor>` suffix on these only.
    local ld_loaders=(ld-linux ld-musl 'libc\.musl')

    # IFS='|' is scoped to the subshell so the rest of the function's
    # `read` loop still splits on whitespace. Anchoring on the full
    # soname stops e.g. libdleak.so.1 from masquerading as libdl.
    local skip_re
    skip_re=$(IFS='|'; echo "^((${system_libs[*]})|(${ld_loaders[*]})-[^.]+)\.so(\.[0-9]+)*$")

    local ldd_out
    ldd_out=$(ldd "${installed_so}" 2>&1) || {
        echo "ERROR: ldd failed for ${installed_so}:" >&2
        echo "${ldd_out}" >&2
        exit 1
    }

    echo "==> Bundling velox-connector shared library dependencies..."
    # ldd line shapes:
    #   <soname> => <abs-path> (<addr>)   resolved — bundle if not system
    #   <soname> => not found             unresolved — fail at end
    # Anything else (vdso, ld-linux without `=>`, blanks) is silently skipped.
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
        echo "ERROR: unresolved shared library deps for ${installed_so}:" >&2
        printf '  %s\n' "${missing[@]}" >&2
        exit 1
    fi

    echo "==> Patching velox-connector RUNPATHs..."
    # PREPEND $ORIGIN-relative paths on both bundled libs and the main .so,
    # preserving any build-time RUNPATH so dlopen() backends (codec engines,
    # plugin loaders) keep finding their resources.
    local old new
    for lib in "${bundled_dir}"/*.so*; do
        [[ -f "${lib}" ]] || continue
        new='$ORIGIN'
        old=$(patchelf --print-rpath "${lib}" 2>/dev/null || true)
        [[ -n "${old}" && "${old}" != "${new}" ]] && new+=":${old}"
        patchelf --set-rpath "${new}" "${lib}"
    done
    # Main .so: $ORIGIN/lib points at the bundled-libs dir alongside it.
    new='$ORIGIN/lib'
    old=$(patchelf --print-rpath "${installed_so}" 2>/dev/null || true)
    [[ -n "${old}" && "${old}" != "${new}" ]] && new+=":${old}"
    patchelf --set-rpath "${new}" "${installed_so}"
}

echo "==> Staging payload..."
presto_jar_install="${payload}${PRESTO_JAR_DIR}"
velox_so_install="${payload}${VELOX_SO_DIR}"
mkdir -p "${presto_jar_install}" "${velox_so_install}"

cp "${jar_file}" "${presto_jar_install}/clp-plugin-presto-connector.jar"
cp "${so_file}" "${velox_so_install}/libclp-plugin-velox-connector.so"

bundle_velox_shared_libraries "${velox_so_install}/libclp-plugin-velox-connector.so"

# Strip bundled third-party libs (folly, glog, boost, etc.) — symbol tables
# and debug info there mostly bloat the package without aiding diagnosis. Our
# own .so is left unstripped so crash backtraces resolve to source.
find "${velox_so_install}/lib" -type f -name '*.so*' \
    -exec strip --strip-unneeded {} +

# cp may preserve source mode; force 0644 on installed files.
chmod 0644 \
    "${presto_jar_install}/clp-plugin-presto-connector.jar" \
    "${velox_so_install}/libclp-plugin-velox-connector.so"
find "${velox_so_install}/lib" -type f -exec chmod 0644 {} +

# ── Emit packages ─────────────────────────────────────────────────────────────

build_deb() {
    local deb_version="${pkg_version_normalized}-1"
    local staging="${build_root}/staging-deb"
    local deb_file="${build_root}/clp-plugin-presto-connector_${deb_version}_${arch}.deb"

    rm -rf "${staging}"
    cp -a "${payload}" "${staging}"
    mkdir -p "${staging}/DEBIAN"
    PKG_ARCH="${arch}" deb_version="${deb_version}" \
        envsubst '$deb_version $PKG_ARCH' \
        < "${pkg_specs_dir}/deb/clp-plugin-presto-connector.control.in" \
        > "${staging}/DEBIAN/control"

    echo "==> Building .deb..."
    dpkg-deb --build --root-owner-group "${staging}" "${deb_file}"
    echo "    -> ${deb_file}"
}

build_rpm() {
    local rpm_version="${pkg_version_normalized}"
    local rpmbuild_dir="${build_root}/rpmbuild"
    local rpm_filename="clp-plugin-presto-connector-${rpm_version}-1.${rpm_arch}.rpm"
    local rpm_file_out="${build_root}/${rpm_filename}"

    rm -rf "${rpmbuild_dir}"
    # rpmbuild creates BUILD/SOURCES/SRPMS on demand; only SPECS+RPMS needed.
    mkdir -p "${rpmbuild_dir}"/{SPECS,RPMS}
    cp "${pkg_specs_dir}/rpm/clp-plugin-presto-connector.spec" \
       "${rpmbuild_dir}/SPECS/clp-plugin-presto-connector.spec"

    echo "==> Building .rpm..."
    rpmbuild \
        --define "_topdir ${rpmbuild_dir}" \
        --define "pkg_version ${rpm_version}" \
        --define "pkg_release 1" \
        --define "payload_dir ${payload}" \
        --define "presto_jar_dir ${PRESTO_JAR_DIR}" \
        --define "velox_so_dir ${VELOX_SO_DIR}" \
        --target "${rpm_arch}" \
        --bb "${rpmbuild_dir}/SPECS/clp-plugin-presto-connector.spec"

    cp "${rpmbuild_dir}/RPMS/${rpm_arch}/${rpm_filename}" "${rpm_file_out}"
    echo "    -> ${rpm_file_out}"
}

build_tarball() {
    local tar_dirname="clp-plugin-presto-connector-${version}-linux-${arch}"
    local staging="${build_root}/staging-tar"
    local tar_file="${build_root}/${tar_dirname}.tar.gz"
    local tar_root="${staging}/${tar_dirname}"

    # The tarball is the portable artifact and uses a canonical
    # `coordinator/` + `worker/` layout. PRESTO_JAR_DIR / VELOX_SO_DIR govern
    # only where the .deb/.rpm install to.
    rm -rf "${staging}"
    mkdir -p "${tar_root}/coordinator" "${tar_root}/worker"
    cp -a "${payload}${PRESTO_JAR_DIR}/." "${tar_root}/coordinator/"
    cp -a "${payload}${VELOX_SO_DIR}/."   "${tar_root}/worker/"

    echo "==> Building .tar.gz..."
    tar -C "${staging}" --owner=0 --group=0 --numeric-owner \
        -czf "${tar_file}" "${tar_dirname}"
    echo "    -> ${tar_file}"
}

build_deb
build_rpm
build_tarball

# ── Copy artifacts ────────────────────────────────────────────────────────────

echo ""
echo "==> Copying artifacts to ${output_dir}..."
cp "${build_root}"/clp-plugin-presto-connector*.deb \
   "${build_root}"/clp-plugin-presto-connector*.rpm \
   "${build_root}"/clp-plugin-presto-connector*.tar.gz \
   "${output_dir}/"

echo ""
echo "========================================"
echo "Build complete"
echo "========================================"
ls -lh "${output_dir}"/clp-plugin-presto-connector*
