#!/usr/bin/env bash

# Builds the busybox init-container installer image from a connector package tarball.
#
# The image bundles both plugins (coordinator JAR + native worker .so and lib/) and, when
# run, installs each into a mounted target directory. See tools/build-packages/README.md.
#
# Reusable by local builds (build-packages.sh, --load) and CI (--push). Prints the built
# image reference to stdout.
#
# Requires: docker (with buildx), git, tar.

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
image_dir="${script_dir}/image"

# Shared helpers: image_repo_from_origin (GHCR repo derivation) and _REPO_ROOT.
source "${script_dir}/dependency-image/utils.sh"

show_help() {
    cat <<'EOF'
Usage: ./tools/build-packages/build-installer-init-image.sh --tarball FILE [OPTIONS]

Builds the busybox init-container installer image from a connector package tarball
(clp-plugin-presto-connector-<version>-linux-<arch>.tar.gz).

Options:
  --tarball FILE   Package tarball to build the image from (required)
  --version VER    Image version tag (default: parsed from the tarball name)
  --arch ARCH      amd64 or arm64 (default: parsed from the tarball name)
  --repo REPO      Image repository (default: derived from the git origin remote,
                    e.g. ghcr.io/y-scope/clp-plugin-presto-connector)
  --push           Push the image to the registry (default: --load into local docker)
  --load           Load the image into the local docker daemon (default)
  --help           Show this help

See tools/build-packages/README.md for details.
EOF
}

die() {
    echo >&2 "ERROR: $*"
    exit 1
}

require_value() {
    [[ -n "${2:-}" ]] || die "$1 requires a value"
}

# ── Parse arguments ───────────────────────────────────────────────────────────

tarball=""
version=""
arch=""
repo=""
output="--load"

while [[ $# -gt 0 ]]; do
    case $1 in
        --tarball) require_value "$1" "${2:-}"; tarball="$2"; shift 2 ;;
        --version) require_value "$1" "${2:-}"; version="$2"; shift 2 ;;
        --arch)    require_value "$1" "${2:-}"; arch="$2";    shift 2 ;;
        --repo)    require_value "$1" "${2:-}"; repo="$2";    shift 2 ;;
        --push)    output="--push"; shift ;;
        --load)    output="--load"; shift ;;
        --help)    show_help; exit 0 ;;
        *) die "unknown option: $1 (use --help for usage)" ;;
    esac
done

[[ -n "${tarball}" ]] || die "--tarball is required (use --help for usage)"
[[ -f "${tarball}" ]] || die "tarball not found: ${tarball}"

command -v docker &>/dev/null || die "docker is required"
docker buildx version &>/dev/null || die "docker buildx is required"

# ── Resolve version and arch from the tarball name when not given ──────────────

# Tarball name format: clp-plugin-presto-connector-<version>-linux-<arch>.tar.gz
tar_base="$(basename "${tarball}")"
tar_base="${tar_base%.tar.gz}"
name_rest="${tar_base#clp-plugin-presto-connector-}"
if [[ "${name_rest}" == "${tar_base}" || "${name_rest}" != *-linux-* ]]; then
    die "cannot parse tarball name '${tar_base}'; pass --version and --arch explicitly"
fi
[[ -n "${arch}" ]] || arch="${name_rest##*-linux-}"
[[ -n "${version}" ]] || version="${name_rest%-linux-"${arch}"}"

case "${arch}" in
    amd64) platform="linux/amd64" ;;
    arm64) platform="linux/arm64" ;;
    *) die "unsupported arch: ${arch} (expected amd64 or arm64)" ;;
esac

[[ -n "${repo}" ]] || repo="$(image_repo_from_origin)"

# Docker tags allow only [A-Za-z0-9_.-]; sanitize any other version characters (e.g. '+').
tag_version="${version//[^A-Za-z0-9_.-]/_}"
image="${repo}:${tag_version}-${arch}"

# ── Assemble a self-contained build context and build ─────────────────────────

context_dir="$(mktemp -d)"
trap 'rm -rf "${context_dir}"' EXIT

# Extract the install tree so coordinator/ and worker/ sit at the context root, matching the
# Dockerfile's COPY paths. --strip-components=1 drops the versioned top-level directory.
tar -xzf "${tarball}" -C "${context_dir}" --strip-components=1
[[ -d "${context_dir}/coordinator" && -d "${context_dir}/worker" ]] \
    || die "tarball did not contain coordinator/ and worker/ trees"

cp "${image_dir}/Dockerfile" "${image_dir}/entrypoint.sh" "${context_dir}/"

echo >&2 "==> Building installer image ${image} (${platform})..."
docker buildx build \
    --platform "${platform}" \
    --tag "${image}" \
    "${output}" \
    -f "${context_dir}/Dockerfile" \
    "${context_dir}"

echo >&2 "==> Built ${image}"
echo "${image}"
