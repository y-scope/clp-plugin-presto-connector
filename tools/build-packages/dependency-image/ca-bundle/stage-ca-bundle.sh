#!/usr/bin/env bash

# Stage the host's CA certificate bundle to a build-context path.
# See ca-bundle.sh for motivation.
#
# Usage: stage-ca-bundle.sh <dest-path>

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${script_dir}/ca-bundle.sh"

stage_host_ca_bundle "${1:?stage-ca-bundle.sh requires a destination path}"
