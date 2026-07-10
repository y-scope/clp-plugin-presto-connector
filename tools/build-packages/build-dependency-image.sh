#!/usr/bin/env bash

# Resolves this repo's dependency-image reference for local builds.
# Checks local Docker first, then GHCR, then builds a host-arch image.
#
# Prints the resolved image reference to stdout.
#
# Example:
#   image=$(tools/build-packages/build-dependency-image.sh)
#   docker run --rm -v "$(pwd):/src" -w /src "${image}" \
#       task velox-connector:build
#
# Requires: docker (with buildx), git, sha256sum.

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${script_dir}/dependency-image/utils.sh"

# Derive this repo's GHCR namespace from its GitHub origin remote.
image_repo_from_origin() {
    local remote_url owner_repo
    remote_url="$(git -C "${_REPO_ROOT}" remote get-url origin)"
    case "${remote_url}" in
        https://github.com/*) owner_repo="${remote_url#https://github.com/}" ;;
        git@github.com:*) owner_repo="${remote_url#git@github.com:}" ;;
        ssh://git@github.com/*) owner_repo="${remote_url#ssh://git@github.com/}" ;;
        *)
            echo "ERROR: can't derive GHCR image repo from origin remote: ${remote_url}" >&2
            echo "       Expected a github.com remote." >&2
            exit 1
            ;;
    esac
    owner_repo="${owner_repo%.git}"
    printf 'ghcr.io/%s\n' "$(printf '%s' "${owner_repo}" | tr '[:upper:]' '[:lower:]')"
}

host_platform() {
    case "$(uname -m)" in
        x86_64) printf 'linux/amd64\n' ;;
        aarch64|arm64) printf 'linux/arm64\n' ;;
        *) echo "ERROR: unsupported host arch: $(uname -m)" >&2; exit 1 ;;
    esac
}

main() {
    local build_env_hash image image_repo platform pull_err

    echo "==> Deriving build-env hash..." >&2
    build_env_hash="$(derive_build_env_hash)"
    image_repo="$(image_repo_from_origin)"
    image="$(image_ref "${image_repo}" "build-env" "${build_env_hash}")"
    platform="$(host_platform)"

    echo >&2 "    build-env hash: ${build_env_hash}"
    echo >&2 "    image:          ${image}"

    if docker image inspect "${image}" &>/dev/null; then
        echo >&2 "==> Found in local Docker cache."
        echo "${image}"
        return
    fi

    echo "==> Checking repository registry..." >&2
    if pull_err="$(docker pull "${image}" 2>&1)"; then
        echo "==> Pulled from repository registry." >&2
        echo "${image}"
        return
    fi

    echo >&2 "    docker pull failed; will build from scratch. Pull error:"
    printf '%s\n' "${pull_err}" | sed 's/^/      /' >&2

    echo >&2 "==> Image not available — building from scratch..."
    build_image "${image}" "${platform}" "--load"
    echo >&2 "==> Built locally."
    echo "${image}"
}

main
