#!/usr/bin/env bash

# Detects and stages the host's CA certificate bundle to a given destination
# path so it can be COPY'd into a Docker build context.
# See ca-bundle.sh for motivation.
#
# Usage: stage-ca-bundle.sh <dest-path>

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=ca-bundle.sh
source "${script_dir}/ca-bundle.sh"

stage_host_ca_bundle "${1:?stage-ca-bundle.sh requires a destination path}"
