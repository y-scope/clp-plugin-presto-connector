#!/usr/bin/env bash

# Resolves the clp-plugin-presto-connector build-env image for the host
# architecture, building it from scratch if neither the local Docker cache
# nor the upstream registry has it.
#
# Prints the resolved image reference to stdout.
#
# Use this when you don't run on GitHub Actions and need to provision the
# build environment yourself (e.g. internal CI, local builds):
#
#   image=$("${this_script}")
#   docker run --rm -v "$(pwd):/src" -w /src "${image}" \
#       bash tools/build-packages/build.sh
#
# Requires: docker (with buildx), cmake >= 3.28, git.

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tools/build-packages/dependency-image/lib.sh
source "${script_dir}/dependency-image/lib.sh"

# Where to look for a prebuilt image. y-scope publishes the canonical
# build-env to its GHCR namespace; override via env if you maintain your
# own mirror.
UPSTREAM_IMAGE_REPO="${UPSTREAM_IMAGE_REPO:-ghcr.io/y-scope/clp-plugin-presto-connector}"
IMAGE_NAME="${IMAGE_NAME:-build-env}"

for cmd in docker cmake git; do
    command -v "${cmd}" &>/dev/null || {
        echo "ERROR: required command '${cmd}' not found in PATH" >&2
        exit 1
    }
done

case "$(uname -m)" in
    x86_64)        host_arch="amd64" ;;
    aarch64|arm64) host_arch="arm64" ;;
    *) echo "ERROR: unsupported host arch: $(uname -m)" >&2; exit 1 ;;
esac

# ── Derive velox SHA ──────────────────────────────────────────────────────────

echo "==> Deriving velox SHA..." >&2
{ read -r velox_sha; read -r velox_scripts; } < <(derive_velox_sha)
image=$(image_ref "${UPSTREAM_IMAGE_REPO}" "${IMAGE_NAME}" "${velox_sha}")
echo "    velox SHA: ${velox_sha}" >&2
echo "    image:     ${image}" >&2

# ── 1. Local Docker cache ─────────────────────────────────────────────────────

if docker image inspect "${image}" &>/dev/null; then
    echo "==> Found in local Docker cache." >&2
    echo "${image}"
    exit 0
fi

# ── 2. Upstream registry (anonymous pull) ─────────────────────────────────────

echo "==> Checking upstream registry..." >&2
# Capture stderr so a real failure (network, registry down, auth) surfaces
# instead of looking identical to "image legitimately doesn't exist."
if pull_err=$(docker pull "${image}" 2>&1 >/dev/null); then
    echo "==> Pulled from upstream." >&2
    echo "${image}"
    exit 0
fi
echo "    docker pull failed; will build from scratch. Pull error:" >&2
echo "${pull_err}" | sed 's/^/      /' >&2

# ── 3. Build from scratch ─────────────────────────────────────────────────────

echo "==> Image not available — building from scratch (~2 hours)..." >&2
build_image "${image}" "linux/${host_arch}" "${velox_scripts}" "--load"
echo "==> Built locally." >&2
echo "${image}"
