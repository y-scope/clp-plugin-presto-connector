#!/usr/bin/env bash

# Host-side helpers for build-env image identity and Docker builds.

if [[ "${_BUILD_ENV_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _BUILD_ENV_SH_LOADED=1

_BUILD_ENV_HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly _BUILD_ENV_HOST_DIR
# shellcheck source=tools/build-packages/internal/ca-trust/host.sh
source "${_BUILD_ENV_HOST_DIR}/../ca-trust/host.sh"

_REPO_ROOT="$(cd "${_BUILD_ENV_HOST_DIR}/../../../.." &>/dev/null && pwd)"
readonly _REPO_ROOT

# Keep local builds working when the checkout lacks initialized submodules.
_ensure_build_env_submodules() {
    git -C "${_REPO_ROOT}" \
        submodule update --init --recursive tools/yscope-dev-utils
}

# Formats the canonical image reference.
#
# Args: <repository> <image-name> <build-env-hash>
image_ref() {
    if (( $# != 3 )) || [[ -z "$1" || -z "$2" || -z "$3" ]]; then
        echo >&2 "ERROR: image_ref requires a repository, image name, and build-env hash"
        return 2
    fi
    local repository="$1"
    local image_name="$2"
    local build_env_hash="$3"
    printf '%s/%s:env-%s\n' "${repository}" "${image_name}" "${build_env_hash}"
}

# Computes the 16-character source/configuration hash used in the image tag.
derive_build_env_hash() (
    set -o errexit
    set -o pipefail
    export LC_ALL=C

    local hash_inputs=(
        ".dockerignore"
        "taskfile.yaml"
        "taskfiles"
        "tools/build-packages/dependency-image"
        "tools/build-packages/internal/ca-trust/container.sh"
        "tools/build-packages/internal/host/build-env.sh"
        "tools/yscope-dev-utils"
    )

    cd "${_REPO_ROOT}"
    _ensure_build_env_submodules >&2

    local stat_mode_cmd=(stat -c '%a')
    if ! "${stat_mode_cmd[@]}" -- "${_REPO_ROOT}" &>/dev/null; then
        stat_mode_cmd=(stat -f '%A')
    fi

    local sha256_cmd=(sha256sum)
    if ! command -v sha256sum &>/dev/null; then
        sha256_cmd=(shasum -a 256)
    fi

    {
        git ls-files -z --cached --recurse-submodules -- "${hash_inputs[@]}"
        git ls-files -z --others --exclude-standard -- "${hash_inputs[@]}"
        git -C tools/yscope-dev-utils ls-files -z --others --exclude-standard \
            | while IFS= read -r -d '' rel_file; do
                printf '%s\0' "tools/yscope-dev-utils/${rel_file}"
            done
    } \
        | sort -zu \
        | while IFS= read -r -d '' file; do
            # Skip tracked files deleted in the working tree. Include untracked,
            # non-ignored inputs so local image tags reflect pre-commit work.
            if [[ -L "${file}" ]]; then
                printf 'symlink %q ' "${file}"
                readlink -- "${file}"
            elif [[ -f "${file}" ]]; then
                file_mode=$("${stat_mode_cmd[@]}" -- "${file}")
                executable_mode=$((8#${file_mode} & 8#111))
                printf 'file %03o ' "${executable_mode}"
                "${sha256_cmd[@]}" -- "${file}"
            fi
        done \
        | "${sha256_cmd[@]}" \
        | cut -c1-16
)

# Builds the build-env image and writes build progress to stderr.
#
# Args:
#   $1  image tag    — e.g. ghcr.io/owner/repo/build-env:env-<hash>
#   $2  platform     — linux/amd64 or linux/arm64
#   $3  output mode  — --push or --load
build_image() {
    if (( $# != 3 )) || [[ -z "$1" || -z "$2" || -z "$3" ]]; then
        echo >&2 "ERROR: build_image requires an image tag, platform, and output mode"
        return 2
    fi
    local tag="$1"
    local platform="$2"
    local output_mode="$3"

    case "${platform}" in
        linux/amd64|linux/arm64) ;;
        *) echo >&2 "ERROR: unsupported build-env platform: ${platform}"; return 1 ;;
    esac
    case "${output_mode}" in
        --push|--load) ;;
        *) echo >&2 "ERROR: unsupported build-env output mode: ${output_mode}"; return 1 ;;
    esac

    local ca_stage
    ca_stage=$(mktemp -d) || return
    (
        set -o errexit
        trap 'rm -rf "${ca_stage}"' EXIT

        local ca_bundle="${ca_stage}/host-ca"
        stage_host_ca_bundle "${ca_bundle}"
        _ensure_build_env_submodules

        # A named context avoids BuildKit's 500 KiB secret limit while the
        # Dockerfile mounts the bundle only into networked RUN steps.
        docker buildx build \
            --platform "${platform}" \
            --build-context "host-ca=${ca_stage}" \
            --tag "${tag}" \
            "${output_mode}" \
            -f "${_REPO_ROOT}/tools/build-packages/dependency-image/Dockerfile" \
            "${_REPO_ROOT}"
    ) >&2
}
