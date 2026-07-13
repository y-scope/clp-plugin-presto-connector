#!/usr/bin/env bash

# Shared dependency-image helpers for tag derivation and Docker builds.
# Callers decide whether to use a local image, pull from GHCR, or build.

if [[ "${_BUILD_ENV_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _BUILD_ENV_SH_LOADED=1

_BUILD_ENV_HOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly _BUILD_ENV_HOST_DIR
_REPO_ROOT="$(cd "${_BUILD_ENV_HOST_DIR}/../../.." &>/dev/null && pwd)"
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
        "tools/yscope-dev-utils"
    )

    cd "${_REPO_ROOT}"
    _ensure_build_env_submodules >&2

    local stat_mode_cmd=(stat -c '%a')
    if ! "${stat_mode_cmd[@]}" -- "${_REPO_ROOT}" &>/dev/null; then
        stat_mode_cmd=(stat -f '%Lp')
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
        _stage_host_ca_bundle "${ca_bundle}" || : > "${ca_bundle}"
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
