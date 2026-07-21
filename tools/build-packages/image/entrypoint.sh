#!/bin/sh

# Init-container installer for the CLP Presto connector plugins.
#
# The image bundles both plugins under /opt/clp-plugin-presto-connector. Because the
# coordinator JAR and the native worker .so install into different locations, each is
# selected independently by its own target env var. Set whichever the pod needs; a
# coordinator pod sets COORDINATOR_PLUGIN_INSTALL_PATH, a worker pod sets WORKER_PLUGIN_INSTALL_PATH, and
# either or both may be set in a single run.

set -eu

readonly PLUGIN_ROOT="/opt/clp-plugin-presto-connector"

usage() {
    cat >&2 <<EOF
ERROR: no install path set. Set at least one of these env vars to a mounted, writable
directory, and this installer copies the matching plugin into it:

  COORDINATOR_PLUGIN_INSTALL_PATH   install ${PLUGIN_ROOT}/coordinator (the Presto plugin JAR) here
  WORKER_PLUGIN_INSTALL_PATH        install ${PLUGIN_ROOT}/worker (the native .so + bundled lib/) here

Example:
  docker run --rm -e WORKER_PLUGIN_INSTALL_PATH=/plugins -v /host/plugins:/plugins <image>
EOF
    exit 1
}

# install_component <source-subdir> <target-dir>
install_component() {
    src="${PLUGIN_ROOT}/$1"
    dest="$2"
    mkdir -p "${dest}"
    # Copy contents (not the subdir itself) so the target holds the plugin files directly.
    cp -a "${src}/." "${dest}/"
    echo "Installed $1 plugin -> ${dest}"
}

installed=0
if [ -n "${COORDINATOR_PLUGIN_INSTALL_PATH:-}" ]; then
    install_component "coordinator" "${COORDINATOR_PLUGIN_INSTALL_PATH}"
    installed=1
fi
if [ -n "${WORKER_PLUGIN_INSTALL_PATH:-}" ]; then
    install_component "worker" "${WORKER_PLUGIN_INSTALL_PATH}"
    installed=1
fi

[ "${installed}" -eq 1 ] || usage
