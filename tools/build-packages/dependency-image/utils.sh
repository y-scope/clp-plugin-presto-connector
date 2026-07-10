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
# Requires: git, sha256sum
derive_build_env_hash() {
    (
        cd "${_REPO_ROOT}" || exit
        ensure_yscope_dev_utils_submodule >&2
        git ls-files -z --recurse-submodules -- "${_BUILD_ENV_HASH_INPUTS[@]}" \
            | LC_ALL=C sort -z  \
            | xargs -0 sha256sum \
            | sha256sum \
            | cut -c1-16
    )
}

# Stages the host CA bundle into the temporary Docker build context.
#
# Args: <destination-path>
_stage_host_ca_bundle() {
    local dest="${1:?_stage_host_ca_bundle requires a destination path}"
    local ca_bundle_candidates=(
        "${SSL_CERT_FILE:-}"
        /etc/ssl/certs/ca-certificates.crt
        /etc/pki/tls/certs/ca-bundle.crt
        /etc/ssl/cert.pem
    )

    local src
    for src in "${ca_bundle_candidates[@]}"; do
        [[ -f "${src}" && -s "${src}" ]] || continue
        echo >&2 "==> Staging host CA bundle: ${src} -> ${dest}"
        if ! cp "${src}" "${dest}"; then
            echo >&2 "ERROR: failed to stage host CA bundle: ${src}"
            return 1
        fi
        return 0
    done

    echo >&2 "==> No host CA bundle found; continuing without host CA context."
    return 1
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

    # Expose the host CA bundle as a narrow named build context so the Dockerfile
    # can bind-mount it during networked RUN steps without baking it into image
    # layers. Use a real context instead of a BuildKit secret because corporate CA
    # bundles can exceed BuildKit's 500KiB secret limit.
    local ca_stage; ca_stage=$(mktemp -d)
    (
        trap 'rm -rf "${ca_stage}"' EXIT

        local ca_bundle="${ca_stage}/host-ca"
        _stage_host_ca_bundle "${ca_bundle}" || : > "${ca_bundle}"

        ensure_yscope_dev_utils_submodule

        docker buildx build \
            --platform "${platform}" \
            --build-context "host-ca=${ca_stage}" \
            --tag "${tag}" \
            "${output}" \
            -f "${_REPO_ROOT}/tools/build-packages/dependency-image/Dockerfile" \
            "${_REPO_ROOT}"
    )
}
