#!/usr/bin/env bash
# Stage the host's CA certificate bundle for container builds.
# Useful when corporate TLS interception adds roots trusted by the host but not
# by base images.
#
# Public API:
#   stage_host_ca_bundle <dest-path>   # detect + copy; errors if none found
#
# Override detection by setting SSL_CERT_FILE before calling.

_detect_host_ca_bundle() {
    local paths=(
        "${SSL_CERT_FILE:-}"
        /etc/ssl/certs/ca-certificates.crt # Debian/Ubuntu/Alpine
        /etc/pki/tls/certs/ca-bundle.crt   # RHEL/CentOS/Fedora
        /etc/ssl/cert.pem                  # macOS
    )
    for p in "${paths[@]}"; do
        [[ -n "${p}" && -f "${p}" ]] && { echo "${p}"; return 0; }
    done
    return 1
}

stage_host_ca_bundle() {
    local dest="${1:?stage_host_ca_bundle requires a destination path}"
    local src
    if ! src="$(_detect_host_ca_bundle)"; then
        echo "ERROR: no CA certificate bundle found on host" >&2
        echo "       expected one of /etc/ssl/certs/ca-certificates.crt," >&2
        echo "       /etc/pki/tls/certs/ca-bundle.crt, or /etc/ssl/cert.pem" >&2
        echo "       set SSL_CERT_FILE to override" >&2
        return 1
    fi
    echo "==> Staging host CA bundle: ${src} -> ${dest}" >&2
    cp "${src}" "${dest}"
}
