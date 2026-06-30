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

# Discovers the velox SHA pinned by the current presto commit, via two
# lightweight HTTP-only steps (no clone, no cmake):
#
#   1. grep the presto SHA out of velox-connector/CMakeLists.txt's
#      `set(PRESTO_GIT_TAG "<sha>")` line — the single source of truth
#      for the presto pin
#   2. query GitHub's contents API for the velox submodule entry at
#      that presto commit — returns the velox submodule's gitlink SHA
#
# Echoes the velox SHA on stdout.
#
# Requires: curl, python3
# Optional: GITHUB_TOKEN env (raises GitHub anon-API rate limit from
# 60 to 5000 req/hr; not needed for normal use — this fires once per
# dep-image build).
derive_velox_sha() {
    local cml="${_REPO_ROOT}/velox-connector/CMakeLists.txt"
    local presto_sha
    presto_sha=$(awk '
        /^set\(PRESTO_GIT_TAG "[a-f0-9]{40}"\)/ {
            match($0, /[a-f0-9]{40}/)
            print substr($0, RSTART, 40)
            exit
        }' "${cml}")
    [[ "${presto_sha}" =~ ^[a-f0-9]{40}$ ]] || {
        echo "ERROR: could not extract presto SHA from ${cml}" >&2
        echo "       (expected: set(PRESTO_GIT_TAG \"<40-hex>\"))" >&2
        return 1
    }

    local api_url="https://api.github.com/repos/prestodb/presto/contents/presto-native-execution/velox?ref=${presto_sha}"
    local velox_sha
    # Authenticate when GITHUB_TOKEN is set (raises anon-API rate limit 60→5000 req/hr).
    # Avoid `"${arr[@]}"`-with-empty-array — macOS bash 3.2 treats it as unbound under `set -u`.
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        velox_sha=$(curl -fsS -H "Authorization: Bearer ${GITHUB_TOKEN}" "${api_url}" \
                    | python3 -c 'import json, sys; print(json.load(sys.stdin)["sha"])')
    else
        velox_sha=$(curl -fsS "${api_url}" \
                    | python3 -c 'import json, sys; print(json.load(sys.stdin)["sha"])')
    fi
    [[ "${velox_sha}" =~ ^[a-f0-9]{40}$ ]] || {
        echo "ERROR: GitHub contents API did not return a velox SHA for presto ${presto_sha}" >&2
        echo "       URL: ${api_url}" >&2
        return 1
    }

    echo "${velox_sha}"
}

# Builds the dependency image.
#
# Args:
#   $1  image tag    — e.g. ghcr.io/owner/build-env:velox-<sha>
#   $2  platform     — linux/amd64 or linux/arm64
#   $3  velox SHA    — passed to the Dockerfile as --build-arg VELOX_SHA;
#                      the Dockerfile curls velox's setup-*.sh scripts at
#                      this SHA from raw.githubusercontent.com
#   $4  output flag  — --push (registry) or --load (local docker)
#
# Requires: docker buildx
build_image() {
    local tag="$1" platform="$2" velox_sha="$3" output="$4"

    # Stage the host CA bundle into a tmp file and mount it as a build secret
    # so corporate TLS-intercepting proxies (e.g. Zscaler) don't break the
    # image's in-container `dnf install` etc. `--secret` keeps the bundle
    # bytes out of the build context, the image cache, and the dep-image
    # source dir — only the trust-store mutation persists. An empty file
    # signals "no CA to install" (the common case; CI runners have no
    # corporate proxy).
    local ca_stage; ca_stage=$(mktemp -d)
    trap "rm -rf '${ca_stage}'" RETURN
    local ca_bundle="${ca_stage}/host-ca"
    "${_REPO_ROOT}/tools/ca-bundle/stage-ca-bundle.sh" "${ca_bundle}" \
        || : > "${ca_bundle}"

    docker buildx build \
        --platform "${platform}" \
        --build-arg "VELOX_SHA=${velox_sha}" \
        --build-context "ca-bundle=${_REPO_ROOT}/tools/ca-bundle" \
        --secret "id=host-ca,src=${ca_bundle}" \
        --tag "${tag}" \
        "${output}" \
        -f "${_DEP_IMG_DIR}/Dockerfile" \
        "${_DEP_IMG_DIR}"
}
