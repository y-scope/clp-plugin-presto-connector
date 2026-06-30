#!/usr/bin/env bash

# Host-side wrapper: resolves the build-env image (pulls from upstream if
# available, else builds locally), then runs build.sh inside it. The
# all-in-one local entry point — most users want this rather than stitching
# build-dependency-image.sh + docker run + build.sh by hand.
#
# Passes all script args straight through to build.sh (so e.g. `--version VER`
# / `--output DIR` work as documented in build.sh --help).
#
# Requires: docker (with buildx). build-dependency-image.sh's other
# requirements (curl, python3) apply transitively when the build-env image
# must be built from scratch.

set -o errexit
set -o nounset
set -o pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"

show_help() {
    cat <<'EOF'
Usage: ./tools/build-packages/package.sh [OPTIONS]

Host-side wrapper: resolves the build-env image (pulls from upstream if
available, else builds locally), then runs build.sh inside it. This is the
recommended all-in-one entry point — most users want this rather than
stitching build-dependency-image.sh + docker run + build.sh by hand.

Options are forwarded to build.sh:
  --output DIR   Output directory for built packages (default: ./packages)
  --version VER  Override package version
                 (default: derived from presto-connector/pom.xml)
  --help         Show this help

See tools/build-packages/README.md for details.
EOF
}

# Handle --help before any work (submodule init, image resolution) so the
# help menu prints and exits immediately instead of triggering a build.
for arg in "$@"; do
    [[ "${arg}" == "--help" ]] && { show_help; exit 0; }
done

# Init submodules on the host (where the process UID matches the file
# owner) rather than inside the container. Git would otherwise refuse with
# "dubious ownership" because the bind-mounted source tree is owned by the
# host user while the container runs as root.
echo "==> Initializing submodules..."
git -C "${src}" submodule update --init --recursive

echo "==> Resolving build-env image..."
image=$("${src}/tools/build-packages/build-dependency-image.sh")

echo "==> Running build.sh inside ${image}..."
exec docker run --rm \
    -v "${src}:${src}" \
    -w "${src}" \
    "${image}" \
    bash tools/build-packages/build.sh "$@"
