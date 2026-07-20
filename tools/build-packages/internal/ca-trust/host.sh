#!/usr/bin/env bash

# Host-side CA discovery and staging shared by Docker build and run workflows.

if [[ "${_CA_TRUST_HOST_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _CA_TRUST_HOST_SH_LOADED=1

_CA_TRUST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly _CA_TRUST_DIR

# Conventional staged filenames. These match the defaults in container.sh so a
# caller that mounts the trust directory and sets CA_TRUST_DIR gets both stores
# consumed without overriding HOST_CA_BUNDLE / HOST_CA_JAVA_TRUST_STORE.
readonly CA_TRUST_BUNDLE_FILENAME="ca-bundle.pem"
readonly CA_TRUST_JAVA_STORE_FILENAME="truststore.p12"

# In-container mount point for the staged trust directory. Callers bind-mount
# the staging directory here and pass it as CA_TRUST_DIR so build-artifacts.sh /
# container.sh consume the staged stores. Kept in host.sh so the path is defined
# once on the host side rather than hardcoded by each caller.
readonly CA_TRUST_CONTAINER_DIR="/run/ca-trust"

# Copies <src> to <dest>, dropping any certificate whose validity period has
# already ended. A stale corporate CA bundle otherwise gets propagated
# verbatim into CURL_CA_BUNDLE, where OpenSSL (unlike macOS's SecureTransport)
# treats the file as the exclusive trust store: one expired cert anywhere in
# it is enough to break TLS verification for any download whose chain happens
# to rely on it, even though the destination server's own certificate is
# fine. Falls back to a plain copy if openssl isn't on the host, so this never
# becomes a new hard dependency.
#
# Args: <src> <dest>
_stage_ca_bundle_without_expired_certs() {
    local src="$1" dest="$2"
    if ! command -v openssl &>/dev/null; then
        cp "${src}" "${dest}"
        return
    fi

    local total=0 dropped=0
    local cert="" line
    : > "${dest}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        cert+="${line}"$'\n'
        if [[ "${line}" == "-----END CERTIFICATE-----" ]]; then
            total=$((total + 1))
            if printf '%s' "${cert}" | openssl x509 -noout -checkend 0 &>/dev/null; then
                printf '%s' "${cert}" >> "${dest}"
            else
                dropped=$((dropped + 1))
            fi
            cert=""
        fi
    done < "${src}"

    if (( dropped > 0 )); then
        echo >&2 "==> Dropped ${dropped}/${total} expired certificate(s) from host CA bundle"
    fi
}

# Stages the host CA bundle at <trust-dir>/${CA_TRUST_BUNDLE_FILENAME} for a
# temporary Docker mount. Creates an empty file when the host has no CA bundle;
# returns nonzero only on an error.
#
# Args: <trust-dir>
stage_host_ca_bundle() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: stage_host_ca_bundle requires a trust directory"
        return 2
    fi
    local trust_dir="$1"
    if [[ -L "${trust_dir}" || ( -e "${trust_dir}" && ! -d "${trust_dir}" ) ]]; then
        echo >&2 "ERROR: stage_host_ca_bundle target is not a directory: ${trust_dir}"
        return 1
    fi
    if ! mkdir -p "${trust_dir}"; then
        echo >&2 "ERROR: failed to create trust directory: ${trust_dir}"
        return 1
    fi
    trust_dir="$(cd "${trust_dir}" &>/dev/null && pwd)" || return
    local dest="${trust_dir}/${CA_TRUST_BUNDLE_FILENAME}"
    if [[ -L "${dest}" || ( -e "${dest}" && ! -f "${dest}" ) ]]; then
        echo >&2 "ERROR: host CA bundle destination is not a regular file: ${dest}"
        return 1
    fi
    local source_path=""
    local candidates=()

    if [[ -n "${SSL_CERT_FILE:-}" ]]; then
        if [[ ! -f "${SSL_CERT_FILE}" || ! -s "${SSL_CERT_FILE}" ]]; then
            echo >&2 "ERROR: SSL_CERT_FILE is not a nonempty regular file: ${SSL_CERT_FILE}"
            return 1
        fi
        candidates=("${SSL_CERT_FILE}")
    else
        candidates=(
            /etc/ssl/certs/ca-certificates.crt
            /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
            /etc/pki/tls/certs/ca-bundle.crt
            /etc/ssl/ca-bundle.pem
            /etc/pki/tls/cacert.pem
            /etc/ssl/cert.pem
        )
    fi

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}" && -s "${candidate}" ]]; then
            source_path="${candidate}"
            break
        fi
    done

    if [[ -n "${source_path}" && -e "${dest}" && "${source_path}" -ef "${dest}" ]]; then
        echo >&2 "ERROR: host CA bundle source and destination must differ: ${dest}"
        return 1
    fi

    local staged_bundle
    if ! staged_bundle="$(mktemp "${trust_dir}/.ca-bundle.XXXXXX")"; then
        echo >&2 "ERROR: failed to create temporary host CA bundle in: ${trust_dir}"
        return 1
    fi
    if [[ -n "${source_path}" ]]; then
        echo >&2 "==> Staging host CA bundle: ${source_path} -> ${dest}"
        if ! _stage_ca_bundle_without_expired_certs "${source_path}" "${staged_bundle}"; then
            rm -f "${staged_bundle}"
            echo >&2 "ERROR: failed to stage host CA bundle: ${source_path}"
            return 1
        fi
    else
        echo >&2 "==> No host CA bundle found; continuing without host CA context."
    fi

    # BuildKit and runtime containers consume the staged bundle read-only.
    if ! chmod 0444 "${staged_bundle}"; then
        rm -f "${staged_bundle}"
        echo >&2 "ERROR: failed to set host CA bundle permissions: ${dest}"
        return 1
    fi
    if ! mv -f "${staged_bundle}" "${dest}"; then
        rm -f "${staged_bundle}"
        echo >&2 "ERROR: failed to replace host CA bundle: ${dest}"
        return 1
    fi
}

# Stages a Java PKCS#12 trust store at <trust-dir>/${CA_TRUST_JAVA_STORE_FILENAME}
# containing the selected JDK's default certificates plus those from the bundle
# at <trust-dir>/${CA_TRUST_BUNDLE_FILENAME}. Run stage_host_ca_bundle first.
#
# Args: <trust-dir>
# The subshell keeps the cleanup trap local to this invocation.
stage_java_pkcs12() (
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: stage_java_pkcs12 requires a trust directory"
        return 2
    fi

    local trust_dir="$1"
    if [[ -L "${trust_dir}" || ( -e "${trust_dir}" && ! -d "${trust_dir}" ) ]]; then
        echo >&2 "ERROR: stage_java_pkcs12 target is not a directory: ${trust_dir}"
        return 1
    fi
    trust_dir="$(cd "${trust_dir}" &>/dev/null && pwd)" || {
        echo >&2 "ERROR: stage_java_pkcs12 cannot enter trust directory: $1"
        return 1
    }
    local input_bundle="${trust_dir}/${CA_TRUST_BUNDLE_FILENAME}"
    local dest="${trust_dir}/${CA_TRUST_JAVA_STORE_FILENAME}"
    if [[ ! -f "${input_bundle}" || ! -r "${input_bundle}" ]]; then
        echo >&2 "ERROR: input CA bundle is not a readable regular file: ${input_bundle}"
        return 1
    fi
    if [[ -L "${dest}" || ( -e "${dest}" && ! -f "${dest}" ) ]]; then
        echo >&2 "ERROR: Java PKCS#12 destination is not a regular file: ${dest}"
        return 1
    fi
    if [[ "${input_bundle}" == "${dest}" ]] \
            || [[ -e "${dest}" && "${input_bundle}" -ef "${dest}" ]]; then
        echo >&2 "ERROR: input CA bundle and Java PKCS#12 destination must differ"
        return 1
    fi

    local generator_dir
    generator_dir="$(cd "${_CA_TRUST_DIR}/generators/java-pkcs12" &>/dev/null && pwd)" || return
    local generator_image="${CA_TRUST_JAVA_PKCS12_GENERATOR_IMAGE:-docker.io/library/eclipse-temurin:17.0.19_10-jdk-jammy@sha256:723151f3fc88ca2060153ee08ab8dbbea7983d6ed6f2622fe440acf178737c94}"
    local container_assets="/opt/clp-trust-store"
    local container_input="/run/secrets/host-ca"
    local container_output_dir="/tmp/clp-java-trust"
    local container_output="${container_output_dir}/truststore.p12"
    local generator_stage=""
    trap '[[ -z "${generator_stage}" ]] || rm -rf "${generator_stage}"' EXIT
    if ! generator_stage="$(mktemp -d "${trust_dir}/.java-pkcs12.XXXXXX")"; then
        echo >&2 "ERROR: failed to create private Java PKCS#12 staging directory in: ${trust_dir}"
        return 1
    fi
    local staged_trust_store
    staged_trust_store="${generator_stage}/truststore.p12"
    # Use the host identity so bind-mounted output remains owned by the caller.
    if ! docker run --rm \
        --network none \
        --user "$(id -u):$(id -g)" \
        --entrypoint bash \
        --mount "type=bind,src=${generator_dir},dst=${container_assets},readonly" \
        --mount "type=bind,src=${input_bundle},dst=${container_input},readonly" \
        --mount "type=bind,src=${generator_stage},dst=${container_output_dir}" \
        "${generator_image}" \
        "${container_assets}/generate.sh" "${container_input}" "${container_output}"; then
        echo >&2 "ERROR: failed to generate Java PKCS#12 trust store"
        return 1
    fi
    if [[ ! -s "${staged_trust_store}" ]]; then
        echo >&2 "ERROR: Java PKCS#12 generator produced no output: ${dest}"
        return 1
    fi
    # Publish only a complete, read-only trust store.
    if ! chmod 0444 "${staged_trust_store}"; then
        echo >&2 "ERROR: failed to set Java PKCS#12 permissions: ${dest}"
        return 1
    fi
    if ! mv -f "${staged_trust_store}" "${dest}"; then
        echo >&2 "ERROR: failed to replace Java PKCS#12 trust store: ${dest}"
        return 1
    fi
)
