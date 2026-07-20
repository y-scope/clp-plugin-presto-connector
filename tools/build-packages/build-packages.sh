#!/usr/bin/env bash

# User-facing entry point for packaging. Resolves the build-env image, then runs
# internal/container/build-artifacts.sh inside it.
#
# Requires: docker (with buildx), git, and sha256sum or shasum.

set -o errexit
set -o nounset
set -o pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
# shellcheck source=tools/build-packages/internal/build-cache/host.sh
source "${src}/tools/build-packages/internal/build-cache/host.sh"
# shellcheck source=tools/build-packages/internal/ca-trust/host.sh
source "${src}/tools/build-packages/internal/ca-trust/host.sh"

show_help() {
    cat <<'EOF'
Usage: ./tools/build-packages/build-packages.sh [OPTIONS]

User-facing entry point for packaging. Resolves the build-env image, then runs
internal/container/build-artifacts.sh inside it.

Options are forwarded to internal/container/build-artifacts.sh:
  --output DIR   Output directory for built packages (default: ./packages)
  --version VER  Override package version
                 (default: derived from presto-connector/pom.xml)
                 VER must start with a digit and use [0-9A-Za-z.+~-]
  --help         Show this help

See tools/build-packages/README.md for details.
EOF
}

# Resolve the output directory on the host before copying completed artifacts
# into it. Other arguments are forwarded unchanged to build-artifacts.sh.
output_dir="${src}/packages"
build_args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            [[ -n "${2:-}" ]] || { echo >&2 "ERROR: --output requires a value"; exit 1; }
            output_dir="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            build_args+=("$1")
            shift
            ;;
    esac
done

# Run the wrapper as the intended artifact owner. Using sudo would make the
# staging directories and copied artifacts root-owned.
if (( EUID == 0 )); then
    echo >&2 "ERROR: build-packages.sh must run as a non-root user; do not invoke it with sudo."
    exit 1
fi

if [[ "${output_dir}" != /* ]]; then
    output_dir="${src}/${output_dir}"
fi
mkdir -p "${output_dir}"
output_dir="$(cd "${output_dir}" && pwd)"

# Initialize submodules on the host so the source tree is complete before it is
# bind-mounted into the build container.
echo "==> Initializing submodules..."
git -C "${src}" submodule update --init --recursive

echo "==> Resolving build-env image..."
image=$("${src}/tools/build-packages/build-dependency-image.sh")
# FetchContent build state is compatible only with the image inputs identified
# by this hash.
image_hash="${image##*:env-}"
if [[ "${image_hash}" == "${image}" ]]; then
    echo >&2 "ERROR: build-env image lacks an env-<hash> tag: ${image}"
    exit 1
fi

# Keep container output in temporary staging, then copy it to the requested
# directory after the build succeeds.
stage_dir=$(mktemp -d)
trap 'rm -rf "${stage_dir}"' EXIT
artifact_stage="${stage_dir}/artifacts"
mkdir -p "${artifact_stage}"
prepare_build_cache "${src}/.cache" "${image_hash}"

# Stage temporary CA trust stores for the container build: the host PEM CA
# bundle and a Java PKCS#12 trust store merging the JDK defaults with it. Both
# are mounted read-only into the container and cleaned up with stage_dir; they
# never enter image layers, persistent caches, or generated packages. Staged
# files are mode 0444 so the non-root container user can read them.
trust_stage="${stage_dir}/trust"
echo "==> Staging temporary container trust stores..."
stage_container_ca_trust "${trust_stage}"

host_uid=$(id -u)
host_gid=$(id -g)

# Run as the host user so staged files and artifacts aren't root-owned. Bind the
# repo at a stable /repo path so cached CMake state doesn't embed the host
# checkout path. The --env flags below wire the build cache and point HOME /
# TASK_TEMP_DIR at disposable in-container scratch (the non-root user can't
# write to the image's defaults); build-artifacts.sh activates that setup only
# when BUILD_CACHE_DIR is present, so CI (which calls it directly) is unaffected.
# The trust stage is mounted read-only at CA_TRUST_CONTAINER_DIR (defined in
# internal/ca-trust/host.sh) and CA_TRUST_DIR tells build-artifacts.sh to configure
# PEM env vars and the Java trust store. MAVEN_OPTS is forwarded so any host-supplied
# Maven options are preserved; ca-trust/container.sh appends the Java trust-store
# properties to it.
echo "==> Running internal/container/build-artifacts.sh inside ${image}..."
docker run --rm \
    --user "${host_uid}:${host_gid}" \
    --mount "type=bind,src=${src},dst=/repo" \
    --mount "type=bind,src=${artifact_stage},dst=/output" \
    --mount "type=bind,src=${trust_stage},dst=${CA_TRUST_CONTAINER_DIR},readonly" \
    --env "BUILD_CACHE_KEY=${image_hash}" \
    --env "BUILD_CACHE_DIR=/repo/.cache" \
    --env "CLP_PLUGIN_BUILD_DIR=/repo/.cache/build/${image_hash}" \
    --env "HOME=/tmp/clp-plugin-presto-connector-home" \
    --env "TASK_TEMP_DIR=/tmp/clp-plugin-presto-connector-task" \
    --env "CA_TRUST_DIR=${CA_TRUST_CONTAINER_DIR}" \
    --env MAVEN_OPTS \
    -w /repo \
    "${image}" \
    bash /repo/tools/build-packages/internal/container/build-artifacts.sh \
    --output /output ${build_args[@]+"${build_args[@]}"}

echo "==> Copying package artifacts to ${output_dir}..."
# Fail clearly when the build produced no artifacts, instead of passing a
# literal '*' to cp (which happens when the glob has no matches).
if ! compgen -G "${artifact_stage}/*" > /dev/null; then
    echo >&2 "ERROR: no package artifacts were produced under ${artifact_stage}"
    exit 1
fi
cp -f "${artifact_stage}"/* "${output_dir}/"
