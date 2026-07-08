#!/usr/bin/env bash
# Install a CA bundle into the container's RHEL-family trust store.
# Pairs with ca-bundle.sh's host-side staging.
#
# Usage: install-ca-bundle.sh <bundle-path>
set -eux

bundle="${1:?install-ca-bundle.sh requires a bundle path}"

if [[ ! -s "${bundle}" ]]; then
    echo "ERROR: ${bundle} is empty or missing." >&2
    echo "       Stage via tools/ca-bundle/stage-ca-bundle.sh first." >&2
    exit 1
fi

cp "${bundle}" /etc/pki/tls/certs/ca-bundle.crt
cp "${bundle}" /etc/pki/ca-trust/source/anchors/host-ca-bundle.crt
update-ca-trust extract
