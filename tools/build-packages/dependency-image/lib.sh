#!/usr/bin/env bash

# Shared helpers for building the dependency image.
#
# Sourced by:
#   - tools/build-packages/build-dependency-image.sh  (local entry point)
#   - .github/workflows/build-dependency-image.yaml   (CI publish)

# Where this lib.sh lives — same dir as Dockerfile.
_DEP_IMG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
_REPO_ROOT="$(cd "${_DEP_IMG_DIR}/../../.." &>/dev/null && pwd)"

# Builds the canonical image reference for our build-env image. Single
# source of truth for the `:velox-<sha>` tag convention used by both
# CI and the standalone script.
#
# Args: <repo> <image-name> <velox-sha>
image_ref() {
    echo "$1/$2:velox-$3"
}

# Materializes the prestodb/presto source tree at the SHA pinned by
# velox-connector/cmake/PrestoPin.cmake (via the fetch-presto cmake
# helper, which include()s the same pin file), then reads the velox
# SHA out of the cloned tree's submodule pointer.
#
# Echoes two lines on stdout:
#   <velox-sha>
#   <velox-scripts-dir>   (absolute path, suitable for `--build-context velox-scripts=...`)
#
# Requires: cmake, git
derive_velox_sha() {
    cmake \
        -S "${_DEP_IMG_DIR}/../fetch-presto" \
        -B "${_REPO_ROOT}/build/presto-fetch" \
        -DFETCHCONTENT_BASE_DIR="${_REPO_ROOT}/build" >&2

    local presto_src="${_REPO_ROOT}/build/presto_native_execution-src"
    local velox_sha
    velox_sha=$(git -C "${presto_src}" \
            ls-tree HEAD presto-native-execution/velox \
        | awk '{print $3}')
    [[ "${velox_sha}" =~ ^[a-f0-9]{40}$ ]] || {
        echo "ERROR: failed to read velox SHA from presto submodule" >&2
        return 1
    }

    echo "${velox_sha}"
    echo "${presto_src}/presto-native-execution/velox/scripts"
}

# Builds the dependency image.
#
# Args:
#   $1  image tag           — e.g. ghcr.io/owner/build-env:velox-<sha>
#   $2  platform            — linux/amd64 or linux/arm64
#   $3  velox-scripts dir   — abs path returned by derive_velox_sha
#   $4  output flag         — --push (registry) or --load (local docker)
#
# Requires: docker buildx
build_image() {
    local tag="$1" platform="$2" velox_scripts="$3" output="$4"

    # Stage the host CA bundle into the build context so corporate
    # TLS-intercepting proxies (e.g. Zscaler) don't break in-container
    # `dnf install` etc. The Dockerfile treats an empty file as "no CA
    # to install," so a missing host bundle is fine.
    local ca_bundle="${_DEP_IMG_DIR}/ca-certificates.crt"
    "${_REPO_ROOT}/tools/ca-bundle/stage-ca-bundle.sh" "${ca_bundle}" \
        || : > "${ca_bundle}"

    docker buildx build \
        --platform "${platform}" \
        --build-context "velox-scripts=${velox_scripts}" \
        --tag "${tag}" \
        "${output}" \
        -f "${_DEP_IMG_DIR}/Dockerfile" \
        "${_DEP_IMG_DIR}"
}
