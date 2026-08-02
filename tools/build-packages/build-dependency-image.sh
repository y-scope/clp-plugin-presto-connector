#!/usr/bin/env bash

# Resolves this repo's dependency-image reference for local builds.
# Checks local Docker first, then GHCR, then builds a host-arch image.
#
# Prints the resolved image reference to stdout.
#
# Example:
#   image=$(tools/build-packages/build-dependency-image.sh)
#   docker run --rm -v "$(pwd):/src" -w /src "${image}" \
#       task velox-connector:build-with-installed-deps
#
# Options:
#   --with-ca-certs   Propagate the host's CA trust into the image build, for
#                     builds behind a corporate TLS gateway. Only applies when
#                     the image is built rather than found or pulled. Nothing is
#                     baked into the image. Off by default.
#
# Requires: docker (with buildx), git, and sha256sum or shasum.

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${script_dir}/dependency-image/utils.sh"

host_platform() {
    case "$(uname -m)" in
        x86_64) printf 'linux/amd64\n' ;;
        aarch64|arm64) printf 'linux/arm64\n' ;;
        *) echo >&2 "ERROR: unsupported host arch: $(uname -m)"; exit 1 ;;
    esac
}

main() {
    local build_env_hash image image_repo platform pull_err
    local with_ca_certs=0

    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-ca-certs)
                with_ca_certs=1
                shift
                ;;
            *)
                echo >&2 "ERROR: unknown option: $1"
                exit 1
                ;;
        esac
    done

    echo >&2 "==> Deriving build-env hash..."
    build_env_hash="$(derive_build_env_hash)"
    image_repo="$(image_repo_from_origin)"
    image="$(image_ref "${image_repo}" "build-env" "${build_env_hash}")"
    platform="$(host_platform)"

    echo >&2 "    build-env hash: ${build_env_hash}"
    echo >&2 "    image:          ${image}"

    if docker image inspect "${image}" &>/dev/null; then
        if (( with_ca_certs )); then
            echo >&2 "    Note: --with-ca-certs applies only when the image is built; reusing cache."
        fi
        echo >&2 "==> Found in local Docker cache."
        echo "${image}"
        return
    fi

    echo >&2 "==> Checking repository registry..."
    if pull_err="$(docker pull "${image}" 2>&1)"; then
        if (( with_ca_certs )); then
            echo >&2 "    Note: --with-ca-certs applies only when the image is built; pulled instead."
        fi
        echo >&2 "==> Pulled from repository registry."
        echo "${image}"
        return
    fi

    echo >&2 "    docker pull failed; will build from scratch. Pull error:"
    printf '%s\n' "${pull_err}" | sed 's/^/      /' >&2

    echo >&2 "==> Image not available — building from scratch..."
    build_image "${image}" "${platform}" "--load" "${with_ca_certs}"
    echo >&2 "==> Built locally."
    echo "${image}"
}

main "$@"
