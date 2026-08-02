#!/usr/bin/env bash

# Shared dependency-image helpers for tag derivation and Docker builds.
# Callers decide whether to use a local image, pull from GHCR, or build.

_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." &>/dev/null && pwd)"

# Keep local builds working when the checkout lacks initialized submodules.
ensure_yscope_dev_utils_submodule() {
    git -C "${_REPO_ROOT}" submodule update --init --recursive tools/yscope-dev-utils
}

# ── Image identity ────────────────────────────────────────────────────────────

# Builds the canonical `:env-<hash>` image reference.
#
# Args: <repo> <image-name> <build-env-hash>
image_ref() {
    echo "$1/$2:env-$3"
}

# Derives this repo's GHCR namespace from its GitHub origin remote.
image_repo_from_origin() {
    local remote_url owner_repo
    remote_url="$(git -C "${_REPO_ROOT}" remote get-url origin)"
    case "${remote_url}" in
        https://github.com/*) owner_repo="${remote_url#https://github.com/}" ;;
        git@github.com:*) owner_repo="${remote_url#git@github.com:}" ;;
        ssh://git@github.com/*) owner_repo="${remote_url#ssh://git@github.com/}" ;;
        *)
            echo >&2 "ERROR: can't derive GHCR image repo from origin remote: ${remote_url}"
            echo >&2 "       Expected a github.com remote."
            exit 1
            ;;
    esac
    owner_repo="${owner_repo%.git}"
    printf 'ghcr.io/%s\n' "$(printf '%s' "${owner_repo}" | tr '[:upper:]' '[:lower:]')"
}

# Validates a package version for use as a Docker tag and prints it unchanged. Docker tags
# allow only [A-Za-z0-9_.-], so versions containing '+' or '~' (valid in packages) are
# rejected rather than encoded — a lossy substitution would collide distinct versions
# (e.g. '1.0+rc' and '1.0~rc'), and an encoding would produce unreadable tags. The single
# shared definition keeps local builds and the CI manifest job producing identical tags.
#
# Args: <version>
# Fails when the version isn't a digit followed by letters, digits, '.', '_', or '-'.
package_version_to_image_tag() {
    local version="$1"
    [[ "${version}" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || return 1
    printf '%s\n' "${version}"
}

# Inputs that should change the build-env image tag.
_BUILD_ENV_HASH_INPUTS=(
    ".dockerignore"
    ".github/workflows/build-dependency-image.yaml"
    "taskfile.yaml"
    "taskfiles"
    "tools/build-packages/build-dependency-image.sh"
    "tools/build-packages/dependency-image"
    "tools/yscope-dev-utils"
)

# Computes the 16-hex-char hash used in the image tag.
#
# Requires: git, and either sha256sum (Linux) or shasum -a 256 (macOS).
derive_build_env_hash() {
    (
        cd "${_REPO_ROOT}" || exit
        ensure_yscope_dev_utils_submodule >&2

        # macOS ships `shasum` rather than `sha256sum`; pick whichever exists.
        # Both emit the same `<hash>  <file>` format, so the pipeline is unchanged.
        local sha256_cmd=(sha256sum)
        if ! command -v sha256sum &>/dev/null; then
            sha256_cmd=(shasum -a 256)
        fi

        git ls-files -z --recurse-submodules -- "${_BUILD_ENV_HASH_INPUTS[@]}" \
            | LC_ALL=C sort -z  \
            | xargs -0 "${sha256_cmd[@]}" \
            | "${sha256_cmd[@]}" \
            | cut -c1-16
    )
}

# ── Docker build ──────────────────────────────────────────────────────────────

# Builds the dependency image.
#
# Args:
#   $1  image tag       — e.g. ghcr.io/owner/build-env:env-<hash>
#   $2  platform        — linux/amd64 or linux/arm64
#   $3  output flag     — --push (registry) or --load (local docker)
#   $4  with CA certs   — 1 to propagate the host's CA trust (optional, off by
#                         default). For local builds behind a corporate TLS
#                         gateway; CI has no such gateway and passes nothing, so
#                         the Dockerfile's empty `ca_trust` stage applies and the
#                         image keeps its own distro trust store.
#
# Requires: docker buildx, git
build_image() {
    local tag="$1" platform="$2" output="$3" with_ca_certs="${4:-0}"

    # stdout of this function is the caller's image ref; keep git chatter off it.
    ensure_yscope_dev_utils_submodule >&2

    local build_cmd=(
        docker buildx build
        --platform "${platform}"
        --tag "${tag}"
        "${output}"
        -f "${_REPO_ROOT}/tools/build-packages/dependency-image/Dockerfile"
    )

    # String compare, not (( )): an arithmetic context name-resolves a non-numeric
    # argument and aborts under `set -u`.
    if [[ "${with_ca_certs}" != "1" ]]; then
        build_cmd+=("${_REPO_ROOT}")
        "${build_cmd[@]}"
        return
    fi

    # shellcheck source=tools/yscope-dev-utils/exports/docker/ca-trust/host.sh
    source "${_REPO_ROOT}/tools/yscope-dev-utils/exports/docker/ca-trust/host.sh"

    local ca_stage
    ca_stage="$(mktemp -d)"
    (
        trap 'rm -rf "${ca_stage}"' EXIT

        ca_trust_stage_or_fail "${ca_stage}"
        ca_trust_stage_build_context "${ca_stage}"
        ca_trust_add_build_args build_cmd "${ca_stage}"

        build_cmd+=("${_REPO_ROOT}")
        "${build_cmd[@]}"
    )
}
