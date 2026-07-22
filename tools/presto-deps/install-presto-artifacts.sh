#!/usr/bin/env bash

# Ensures the Presto Maven artifacts the connector builds against exist: clones Presto at
# G_PRESTO_GIT_TAG (taskfiles/velox-connector/deps.yaml) and `mvn install`s the modules
# the connector consumes, plus their reactor dependencies, into the local Maven
# repository. presto.version in presto-connector/pom.xml must be that commit's own
# version (this script dies on a mismatch) since its artifacts are published nowhere.
#
# A stamp file under the build directory records the installed commit, so re-runs are
# no-ops until the pin moves; --force rebuilds regardless (e.g. after another Presto
# checkout's `mvn install` shadowed these artifacts in the mutable local repository).
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

# The modules the connector pom consumes; `-am` adds their reactor dependency closure,
# which also covers every sibling module they depend on transitively.
PRESTO_MODULES="presto-common,presto-spi,presto-parser,presto-main-base,presto-tests"

show_help() {
    cat <<'EOF'
Usage: ./tools/presto-deps/install-presto-artifacts.sh [OPTIONS]

Ensures the Presto Maven artifacts for presto-connector/pom.xml's presto.version exist:
builds the pinned Presto commit (G_PRESTO_GIT_TAG) from source and installs the needed
modules into the local Maven repository, remembering the installed commit in a stamp file.

Options:
  --force   Rebuild and reinstall even when the stamp matches the pinned commit
  --help    Show this help
EOF
}

die() {
    echo >&2 "ERROR: $*"
    exit 1
}

force=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --force) force=1; shift ;;
        --help)  show_help; exit 0 ;;
        *) die "unknown option: $1 (use --help for usage)" ;;
    esac
done

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

build_dir="${CLP_PLUGIN_BUILD_DIR:-${repo_root}/build}"
stamp="${build_dir}/presto-artifacts.stamp"
want="${presto_git_tag} ${presto_version}"

if (( !force )) && [[ -f "${stamp}" && "$(cat "${stamp}")" == "${want}" ]]; then
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
    ./mvnw -B -T 1C -pl "${PRESTO_MODULES}" -am install \
        -DskipTests \
        -Dair.check.skip-all=true \
        -Dmaven.javadoc.skip=true \
        -Dmaven.source.skip=true
)

printf '%s\n' "${want}" > "${stamp}"
echo "==> Installed Presto ${presto_version} artifacts from ${presto_git_tag:0:12}."
