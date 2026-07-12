#!/usr/bin/env bash

# Build installable .deb / .rpm / .tar.gz packages.
#
# Must run inside the build-env image. See tools/build-packages/README.md
# for local and CI entry points.

set -o errexit
set -o nounset
set -o pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." &>/dev/null && pwd)"

# Install layout. Overridable via env; also exposed to rpmbuild via --define.
readonly PRESTO_JAR_DIR="${PRESTO_JAR_DIR:-/opt/clp-plugin-presto-connector/coordinator}"
readonly VELOX_SO_DIR="${VELOX_SO_DIR:-/opt/clp-plugin-presto-connector/worker}"
readonly PACKAGE_RELEASE=1

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

See tools/build-packages/README.md for the recommended local entry point.
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

# ── Validate environment ──────────────────────────────────────────────────────

for cmd in cmake dpkg-deb envsubst git javac ldd patchelf readlink rpmbuild strip tar task; do
    command -v "${cmd}" &>/dev/null \
        || die "required command '${cmd}' not found in PATH"
done

[[ -n "${HOME:-}" ]] || die "HOME must be set"

if [[ -z "${JAVA_HOME:-}" ]]; then
    javac_path=$(readlink -f "$(command -v javac)")
    export JAVA_HOME="${javac_path%/bin/javac}"
fi

maven_opts="${MAVEN_OPTS:-}"
[[ -n "${maven_opts}" ]] && maven_opts+=" "
maven_opts+="-Duser.home=${HOME}"
if [[ -n "${MAVEN_USER_HOME:-}" ]]; then
    # MAVEN_USER_HOME also caches the Maven Wrapper distribution, which is
    # separate from Maven's local artifact repository.
    mkdir -p "${MAVEN_USER_HOME}/repository"
    maven_opts+=" -Dmaven.repo.local=${MAVEN_USER_HOME}/repository"
fi

case "$(uname -m)" in
    x86_64)  arch="amd64"; rpm_arch="x86_64"  ;;
    aarch64) arch="arm64"; rpm_arch="aarch64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

pkg_specs_dir="${src}/tools/build-packages/package-specs"
project_build_dir="${CLP_PLUGIN_BUILD_DIR:-${src}/build}"
velox_build_dir="${project_build_dir}/velox-connector"
fetchcontent_base_dir="${FETCHCONTENT_BASE_DIR:-${velox_build_dir}/_deps}"
build_root="${src}/build/packaging"
payload="${build_root}/payload"
artifacts=()

mkdir -p "${output_dir}"
output_dir="$(cd "${output_dir}" && pwd)"
if [[ "${output_dir}" == "${build_root}" || "${output_dir}" == "${build_root}/"* ]]; then
    die "--output must not be ${build_root} or one of its subdirectories"
fi

# Start each run from a clean build_root so stale artifacts from prior runs
# (e.g. a previous --version) cannot leak into the generated packages.
rm -rf "${build_root}"
mkdir -p "${build_root}"

# ── Build velox-connector .so ─────────────────────────────────────────────────

# Submodules are initialized by the caller. Running git inside the container can
# trigger ownership checks because the source tree is bind-mounted from the host.

echo "==> Building velox-connector .so with image-installed dependencies..."
# The build-env image already contains the C++ dependency installations and
# generated all-deps.cmake. Configure and build the plugin without rerunning
# the dependency installation workflow.
task --concurrency 1 -d "${src}" velox-connector:build-with-installed-deps
so_file="${velox_build_dir}/libclp-plugin-velox-connector.so"
[[ -f "${so_file}" ]] || die "expected .so not found at ${so_file}"
echo "    -> ${so_file}"

# ── Derive version ────────────────────────────────────────────────────────────

# Use the Maven wrapper from the Presto source fetched by CMake.
presto_src="${fetchcontent_base_dir}/presto_native_execution-src"
maven_wrapper="${presto_src}/mvnw"
[[ -x "${maven_wrapper}" ]] \
    || die "expected Maven wrapper not found or not executable at ${maven_wrapper}"

run_maven() {
    MAVEN_PROJECTBASEDIR="${presto_src}" \
    MAVEN_OPTS="${maven_opts}" \
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

# rpm Version: forbids '-'. Debian and rpm both sort '~' before the empty
# string, so dash-qualified versions sort before their base release.
pkg_version_normalized="${version//-/\~}"

echo ""
echo "==> CLP Plugin Presto Connector package build"
echo "    Arch:    ${arch}"
echo "    Version: ${version}"
echo "    Output:  ${output_dir}"
echo ""

# ── Build presto-connector .jar ───────────────────────────────────────────────

# Pin Java's user.home to HOME so Maven behaves consistently in local and CI
# containers instead of inferring its home from the container account.
echo "==> Building presto-connector .jar via fetched mvnw..."
run_maven clean package -DskipTests -B

jar_file=$(find "${src}/presto-connector/target" -maxdepth 1 \
    -name 'clp-plugin-presto-connector-*.jar' \
    ! -name '*-sources.jar' ! -name '*-javadoc.jar' \
    -print -quit)
[[ -f "${jar_file}" ]] \
    || die "expected .jar not found in presto-connector/target/"
echo "    -> ${jar_file}"

# ── Stage payload ─────────────────────────────────────────────────────────────

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
    # Bundled libraries live next to the worker plugin under lib/.
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
    ldd_out=$(LC_ALL=C ldd "${installed_so}" 2>&1) || {
        echo >&2 "ERROR: ldd failed for ${installed_so}:"
        echo >&2 "${ldd_out}"
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
        echo >&2 "ERROR: unresolved shared library deps for ${installed_so}:"
        printf >&2 '  %s\n' "${missing[@]}"
        exit 1
    fi

    echo "==> Patching velox-connector RUNPATHs..."
    # PREPEND $ORIGIN-relative paths on both bundled libs and the main .so,
    # preserving any build-time RUNPATH so dlopen() backends (codec engines,
    # plugin loaders) keep finding their resources.
    for lib in "${bundled_dir}"/*.so*; do
        [[ -f "${lib}" ]] || continue
        prepend_runpath '$ORIGIN' "${lib}"
    done
    # Main .so: $ORIGIN/lib points at the bundled-libs dir alongside it.
    prepend_runpath '$ORIGIN/lib' "${installed_so}"
}

echo "==> Staging payload..."
presto_jar_install="${payload}${PRESTO_JAR_DIR}"
velox_so_install="${payload}${VELOX_SO_DIR}"
mkdir -p "${presto_jar_install}" "${velox_so_install}"

cp "${jar_file}" "${presto_jar_install}/clp-plugin-presto-connector.jar"
cp "${so_file}" "${velox_so_install}/libclp-plugin-velox-connector.so"

bundle_velox_shared_libraries "${velox_so_install}/libclp-plugin-velox-connector.so"

# Strip bundled third-party libs (folly, glog, boost, etc.) to keep packages
# smaller. Leave the plugin .so unstripped so crash backtraces resolve to source.
find "${velox_so_install}/lib" -type f -name '*.so*' \
    -exec strip --strip-unneeded {} +

# cp may preserve source mode; force 0644 on installed files.
chmod 0644 \
    "${presto_jar_install}/clp-plugin-presto-connector.jar" \
    "${velox_so_install}/libclp-plugin-velox-connector.so"
find "${velox_so_install}/lib" -type f -exec chmod 0644 {} +

# ── Emit packages ─────────────────────────────────────────────────────────────

build_deb() {
    local deb_version="${pkg_version_normalized}-${PACKAGE_RELEASE}"
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
    artifacts+=("${deb_file}")
    echo "    -> ${deb_file}"
}

build_rpm() {
    local rpm_version="${pkg_version_normalized}"
    local rpmbuild_dir="${build_root}/rpmbuild"
    local rpm_filename="clp-plugin-presto-connector-${rpm_version}-${PACKAGE_RELEASE}.${rpm_arch}.rpm"
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
        --define "pkg_release ${PACKAGE_RELEASE}" \
        --define "payload_dir ${payload}" \
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
    artifacts+=("${tar_file}")
    echo "    -> ${tar_file}"
}

build_deb
build_rpm
build_tarball

# ── Copy artifacts ────────────────────────────────────────────────────────────

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
