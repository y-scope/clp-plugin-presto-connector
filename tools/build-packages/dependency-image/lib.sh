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

# Inputs that should change the build-env image tag.
_BUILD_ENV_HASH_INPUTS=(
    ".github/workflows/build-dependency-image.yaml"
    "taskfile.yaml"
    "taskfiles"
    "tools/build-packages/build-dependency-image.sh"
    "tools/build-packages/dependency-image"
    "tools/ca-bundle"
    "tools/yscope-dev-utils"
)

# Computes the 16-hex-char hash used in the image tag.
#
# Requires: git, sha256sum
derive_build_env_hash() {
    (
        cd "${_REPO_ROOT}"
        ensure_yscope_dev_utils_submodule >&2
        git ls-files -z --recurse-submodules -- "${_BUILD_ENV_HASH_INPUTS[@]}" \
            | sort -z \
            | xargs -0 sha256sum \
            | sha256sum \
            | cut -c1-16
    )
}

# ── Docker build ──────────────────────────────────────────────────────────────

# Builds the dependency image.
#
# Args:
#   $1  image tag    — e.g. ghcr.io/owner/build-env:env-<hash>
#   $2  platform     — linux/amd64 or linux/arm64
#   $3  output flag  — --push (registry) or --load (local docker)
#
# Requires: docker buildx, git
build_image() {
    local tag="$1" platform="$2" output="$3"

    # Mount the host CA bundle as a BuildKit secret so the bundle bytes stay
    # out of the image layers and build context. An empty file means no host CA.
    local ca_stage; ca_stage=$(mktemp -d)
    trap "rm -rf '${ca_stage}'" RETURN
    local ca_bundle="${ca_stage}/host-ca"
    if ! "${_REPO_ROOT}/tools/ca-bundle/stage-ca-bundle.sh" "${ca_bundle}"; then
        : > "${ca_bundle}"
    fi

    ensure_yscope_dev_utils_submodule

    docker buildx build \
        --platform "${platform}" \
        --secret "id=host-ca,src=${ca_bundle}" \
        --tag "${tag}" \
        "${output}" \
        -f "${_REPO_ROOT}/tools/build-packages/dependency-image/Dockerfile" \
        "${_REPO_ROOT}"
}
