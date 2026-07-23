#!/usr/bin/env bash

# Ensures the Presto Maven artifacts the connector builds against exist: clones Presto at
# G_PRESTO_GIT_TAG (taskfiles/velox-connector/deps.yaml) and `mvn install`s the modules
# the connector consumes into the local Maven repository. presto.version in
# presto-connector/pom.xml must be that commit's own version (this script dies on a
# mismatch). Official releases (a purely numeric presto.version from the upstream Presto
# repository) are on Maven Central, so this script exits without building anything.
#
# Installs only the `provided`-scope modules by default (cheap: presto-common/presto-spi);
# --with-test-deps adds the `test`-scope closure (expensive: most of Presto's reactor).
# Builds that skip tests with -Dmaven.test.skip=true never need it.
#
# A stamp file plus an artifact-presence check make re-runs no-ops until the pin moves,
# the repository is purged or replaced, or --with-test-deps asks for modules not yet
# installed; --force rebuilds regardless.
#
# Respects CLP_PLUGIN_BUILD_DIR (default: <repo>/build) and MAVEN_OPTS. Requires: bash,
# sed, git, curl (Maven wrapper + dependency downloads), a JDK.

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
repo_root="$(cd "${script_dir}/../.." &>/dev/null && pwd)"
connector_pom="${repo_root}/presto-connector/pom.xml"
velox_deps_yaml="${repo_root}/taskfiles/velox-connector/deps.yaml"

# The modules presto-connector/pom.xml consumes at `provided` scope: needed to compile its
# main sources, so every caller (packaging and testing alike) installs these.
PRESTO_MODULES_MAIN="presto-common,presto-spi"

# The modules presto-connector/pom.xml consumes at `test` scope.
PRESTO_MODULES_TEST="presto-analyzer,presto-parser,presto-main-base,presto-tests"

# `-am` adds each requested module's reactor dependency closure, which also covers every
# sibling module it depends on transitively.
PRESTO_MODULES="${PRESTO_MODULES_MAIN}"
with_test_deps=0

show_help() {
    cat <<'EOF'
Usage: ./tools/presto-deps/install-presto-artifacts.sh [OPTIONS]

Ensures the Presto Maven artifacts for presto-connector/pom.xml's presto.version exist:
builds the pinned Presto commit (G_PRESTO_GIT_TAG) from source and installs the needed
modules into the local Maven repository, remembering the installed commit in a stamp file.

Options:
  --with-test-deps  Also install the modules needed to compile/run presto-connector's tests
                     (presto-tests, presto-main-base, etc.). Skip this for packaging/release
                     builds, which never compile test sources.
  --force           Rebuild and reinstall even when the stamp matches the pinned commit
  --help            Show this help
EOF
}

die() {
    echo >&2 "ERROR: $*"
    exit 1
}

force=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-test-deps) with_test_deps=1; shift ;;
        --force) force=1; shift ;;
        --help)  show_help; exit 0 ;;
        *) die "unknown option: $1 (use --help for usage)" ;;
    esac
done

if (( with_test_deps )); then
    PRESTO_MODULES="${PRESTO_MODULES_MAIN},${PRESTO_MODULES_TEST}"
fi

[[ -f "${connector_pom}" ]] || die "connector pom not found: ${connector_pom}"
presto_version="$(sed -n 's|.*<presto.version>\(.*\)</presto.version>.*|\1|p' \
    "${connector_pom}" | head -n1)"
[[ -n "${presto_version}" ]] || die "presto.version not found in ${connector_pom}"

# ── Ensure artifacts built from the pinned commit ─────────────────────────────

[[ -f "${velox_deps_yaml}" ]] || die "velox-connector deps taskfile not found: ${velox_deps_yaml}"
presto_git_tag="$(sed -n 's|.*G_PRESTO_GIT_TAG: "\([^"]*\)".*|\1|p' "${velox_deps_yaml}")"
[[ -n "${presto_git_tag}" ]] || die "G_PRESTO_GIT_TAG not found in ${velox_deps_yaml}"
presto_git_url="$(sed -n 's|.*G_PRESTO_GIT_URL: "\([^"]*\)".*|\1|p' "${velox_deps_yaml}")"
[[ -n "${presto_git_url}" ]] || die "G_PRESTO_GIT_URL not found in ${velox_deps_yaml}"

# Official releases (a purely numeric version, e.g. 0.299, from the upstream Presto
# repository) are published to Maven Central, so Maven resolves them without a source
# build. Anything else -- a fork URL, or a version such as 0.299-SNAPSHOT, 0.299-uber,
# or main -- is unpublished and must be built from source.
if [[ "${presto_git_url}" == "https://github.com/prestodb/presto.git" \
    && "${presto_version}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "==> Presto ${presto_version} is a published release; skipping the source build."
    exit 0
fi

build_dir="${CLP_PLUGIN_BUILD_DIR:-${repo_root}/build}"
stamp="${build_dir}/presto-artifacts.stamp"
want="${presto_git_tag} ${presto_version}"
mkdir -p "${build_dir}"

# Serialize concurrent runs (they would race in the source checkout and the local Maven
# repository). The kernel releases the lock when the script exits, however it exits; the
# stamp check below runs under the lock, so a run that waited here sees a fresh stamp.
if command -v flock &>/dev/null; then
    exec 9>"${build_dir}/presto-artifacts.lock"
    flock 9
fi

# The local Maven repository the build actually uses, honoring a -Dmaven.repo.local
# override in MAVEN_OPTS (as the packaging container sets).
maven_repo="${HOME}/.m2/repository"
case " ${MAVEN_OPTS:-}" in
    *"-Dmaven.repo.local="*)
        maven_repo="${MAVEN_OPTS#*-Dmaven.repo.local=}"
        maven_repo="${maven_repo%%[[:space:]]*}"
        ;;
esac

# The stamp alone can lie when the repository was purged, replaced (different MAVEN_OPTS),
# or left incomplete; only skip the build when the artifacts the connector resolves exist.
artifacts_present() {
    local group_dir="${maven_repo}/com/facebook/presto"
    local artifact prefix
    for artifact in ${PRESTO_MODULES//,/ }; do
        # Maven needs each artifact's POM (for the dependency graph) as well as its JAR.
        prefix="${group_dir}/${artifact}/${presto_version}/${artifact}-${presto_version}"
        [[ -f "${prefix}.jar" && -f "${prefix}.pom" ]] || return 1
    done
    if (( with_test_deps )); then
        # presto-connector/pom.xml also resolves presto-main-base's test-jar classifier.
        local tests_jar="${group_dir}/presto-main-base/${presto_version}"
        tests_jar+="/presto-main-base-${presto_version}-tests.jar"
        [[ -f "${tests_jar}" ]] || return 1
    fi
    return 0
}

if (( !force )) && [[ -f "${stamp}" && "$(cat "${stamp}")" == "${want}" ]] && artifacts_present; then
    echo "==> Presto ${presto_version} artifacts already installed from" \
        "${presto_git_tag:0:12} (use --force to rebuild)."
    exit 0
fi

command -v git &>/dev/null || die "git is required"
src_dir="${build_dir}/presto-src"
mkdir -p "${src_dir}"

if [[ ! -d "${src_dir}/.git" ]]; then
    git -C "${src_dir}" init --quiet
    git -C "${src_dir}" remote add origin "${presto_git_url}"
fi
# Keep an existing clone's remote in sync when G_PRESTO_GIT_URL changes.
git -C "${src_dir}" remote set-url origin "${presto_git_url}"

if ! git -C "${src_dir}" cat-file -e "${presto_git_tag}^{commit}" 2>/dev/null; then
    # Prefer copying the commit from a local checkout that already has it (e.g. the CMake
    # FetchContent cache) over fetching it from the network again.
    for candidate in "${repo_root}"/.cache/fetchcontent/*/presto_native_execution-src \
        "${build_dir}/velox-connector/_deps/presto_native_execution-src"; do
        if git -C "${candidate}" cat-file -e "${presto_git_tag}^{commit}" 2>/dev/null \
            && git -C "${src_dir}" fetch --quiet "${candidate}" "${presto_git_tag}" 2>/dev/null
        then
            echo "==> Copied presto@${presto_git_tag:0:12} from ${candidate}."
            break
        fi
    done
fi
if ! git -C "${src_dir}" cat-file -e "${presto_git_tag}^{commit}" 2>/dev/null; then
    echo "==> Fetching presto@${presto_git_tag} from ${presto_git_url}..."
    git -C "${src_dir}" fetch --depth 1 origin "${presto_git_tag}"
fi
git -C "${src_dir}" checkout --quiet --force --detach "${presto_git_tag}"

# The version we install must be the pinned commit's own version, or the connector would
# resolve artifacts that don't correspond to its pom.
ref_version="$(grep -A2 '<artifactId>presto-root</artifactId>' "${src_dir}/pom.xml" \
    | sed -n 's|.*<version>\(.*\)</version>.*|\1|p' | head -n1)"
[[ "${ref_version}" == "${presto_version}" ]] \
    || die "presto.version ${presto_version} != ${ref_version} at presto@${presto_git_tag:0:12};" \
        "update presto-connector/pom.xml to match"

echo "==> Building and installing Presto modules [${PRESTO_MODULES}] and their reactor" \
    "dependencies (first run takes a while)..."
(
    cd "${src_dir}"
    # -DskipUI: presto-main-base's "ui" profile (on by default) pulls in presto-ui as a
    # runtime-only dependency to bundle the web console; the connector never touches it, and
    # building it here would drag in a yarn/npm frontend build for no benefit.
    ./mvnw -B -T 1C -pl "${PRESTO_MODULES}" -am install \
        -DskipTests \
        -DskipUI \
        -Dair.check.skip-all=true \
        -Dmaven.javadoc.skip=true \
        -Dmaven.source.skip=true
)

printf '%s\n' "${want}" > "${stamp}"
echo "==> Installed Presto ${presto_version} artifacts from ${presto_git_tag:0:12}."
