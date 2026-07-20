#!/usr/bin/env bash

# Generates a Java PKCS#12 trust store inside a temporary JDK 17 container.

set -o errexit
set -o nounset
set -o pipefail

if (( $# != 2 )) || [[ -z "$1" || -z "$2" ]]; then
    echo >&2 "ERROR: generate.sh requires an input CA bundle and output path"
    exit 2
fi

input_bundle="$1"
output_trust_store="$2"
if [[ ! -f "${input_bundle}" || ! -r "${input_bundle}" ]]; then
    echo >&2 "ERROR: input CA bundle is not a readable regular file: ${input_bundle}"
    exit 1
fi
output_dir="$(dirname "${output_trust_store}")"
if [[ ! -d "${output_dir}" || ! -w "${output_dir}" ]]; then
    echo >&2 "ERROR: output directory is not writable: ${output_dir}"
    exit 1
fi
if [[ -e "${output_trust_store}" && ! -f "${output_trust_store}" ]]; then
    echo >&2 "ERROR: output path is not a regular file: ${output_trust_store}"
    exit 1
fi

java_home="${JAVA_HOME:-}"
if [[ -z "${java_home}" ]]; then
    java_executable="$(command -v java)" || {
        echo >&2 "ERROR: java was not found in PATH"
        exit 1
    }
    java_executable="$(readlink -f "${java_executable}")"
    java_home="${java_executable%/bin/java}"
else
    java_executable="${java_home}/bin/java"
fi
if [[ ! -x "${java_executable}" ]]; then
    echo >&2 "ERROR: Java executable is not available: ${java_executable}"
    exit 1
fi

java_security_dir="${java_home}/lib/security"
base_java_trust_store="${java_security_dir}/cacerts"
# Match Java's trust-store lookup order: jssecacerts overrides cacerts.
if [[ -f "${java_security_dir}/jssecacerts" && -s "${java_security_dir}/jssecacerts" ]]; then
    base_java_trust_store="${java_security_dir}/jssecacerts"
fi
if [[ ! -f "${base_java_trust_store}" || ! -r "${base_java_trust_store}" \
        || ! -s "${base_java_trust_store}" ]]; then
    echo >&2 "ERROR: Java trust store is not readable: ${base_java_trust_store}"
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Use Java source-file mode to avoid a separate compilation step and class files.
"${java_executable}" "${script_dir}/CreateJavaTrustStore.java" \
    "${input_bundle}" "${base_java_trust_store}" "${output_trust_store}" changeit
