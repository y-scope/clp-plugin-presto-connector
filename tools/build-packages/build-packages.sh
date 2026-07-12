#!/usr/bin/env bash

# User-facing entry point for packaging. Resolves the build-env image, then runs
# internal/container/build-artifacts.sh inside it.
#
# Requires: docker (with buildx), git, sha256sum.

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

# Keep root-owned container output in temporary staging, then copy it to the
# requested directory as the invoking host user.
stage_dir=$(mktemp -d)
trap 'rm -rf "${stage_dir}"' EXIT
artifact_stage="${stage_dir}/artifacts"
trust_stage="${stage_dir}/trust"
ca_bundle="${trust_stage}/ca-bundle.pem"
java_trust_store="${trust_stage}/truststore.p12"
mkdir -p "${artifact_stage}" "${trust_stage}"
prepare_build_cache "${src}/.cache" "${image_hash}"

echo "==> Staging temporary container trust stores..."
stage_host_ca_bundle "${ca_bundle}"
stage_java_pkcs12 "${ca_bundle}" "${java_trust_store}"

# Use a stable container checkout path so cached CMake state does not embed the
# host checkout path. HOME and Task scratch data remain in the disposable
# container.
echo "==> Running internal/container/build-artifacts.sh inside ${image}..."
docker run --rm \
    --mount "type=bind,src=${src},dst=/repo" \
    --mount "type=bind,src=${artifact_stage},dst=/output" \
    --mount "type=bind,src=${trust_stage},dst=/run/ca-trust,readonly" \
    --env MAVEN_OPTS \
    --env "BUILD_CACHE_KEY=${image_hash}" \
    -w /repo \
    "${image}" \
    bash -c '
        set -o errexit
        set -o nounset
        set -o pipefail
        export BUILD_CACHE_DIR=/repo/.cache
        export CA_TRUST_DIR=/run/ca-trust
        export HOME=/tmp/clp-plugin-presto-connector-home
        export TASK_TEMP_DIR=/tmp/clp-plugin-presto-connector-task
        source tools/build-packages/internal/build-cache/container.sh
        source tools/build-packages/internal/ca-trust/container.sh
        mkdir -p "${HOME}" "${TASK_TEMP_DIR}"
        umask 0022
        echo "==> Running the package build as root..."
        exec bash tools/build-packages/internal/container/build-artifacts.sh "$@"
    ' bash --output /output "${build_args[@]+"${build_args[@]}"}"

echo "==> Copying package artifacts to ${output_dir}..."
for artifact in "${artifact_stage}"/*; do
    rm -f -- "${output_dir}/$(basename -- "${artifact}")"
    cp -- "${artifact}" "${output_dir}/"
done
