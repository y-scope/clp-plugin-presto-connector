#!/usr/bin/env sh

# Container-side configuration for consuming prepared CA trust stores. Source
# it after setting CA_TRUST_DIR to the read-only mount of the staged directory,
# which must contain ca-bundle.pem and truststore.p12.
if [ -n "${CA_TRUST_DIR:-}" ]; then
    HOST_CA_BUNDLE="${CA_TRUST_DIR}/ca-bundle.pem"
    HOST_CA_JAVA_TRUST_STORE="${CA_TRUST_DIR}/truststore.p12"
fi

if [ -s "${HOST_CA_BUNDLE:-}" ]; then
    export CURL_CA_BUNDLE="${HOST_CA_BUNDLE}"
    export GIT_SSL_CAINFO="${HOST_CA_BUNDLE}"
    export PIP_CERT="${HOST_CA_BUNDLE}"
    export REQUESTS_CA_BUNDLE="${HOST_CA_BUNDLE}"
    export SSL_CERT_FILE="${HOST_CA_BUNDLE}"
fi

# Configure Java from the staged PKCS#12 trust store; fail if it is missing or
# unreadable.
if [ "${HOST_CA_JAVA_TRUST_STORE+x}" = x ]; then
    if [ ! -s "${HOST_CA_JAVA_TRUST_STORE}" ]; then
        echo >&2 "ERROR: Java trust store is not readable: ${HOST_CA_JAVA_TRUST_STORE}"
        return 1
    fi

    # Preserve any Maven options supplied by the caller.
    _host_ca_maven_opts="${MAVEN_OPTS:-}"
    [ -n "${_host_ca_maven_opts}" ] && _host_ca_maven_opts="${_host_ca_maven_opts} "
    _host_ca_maven_opts="${_host_ca_maven_opts}-Djavax.net.ssl.trustStore=${HOST_CA_JAVA_TRUST_STORE}"
    _host_ca_maven_opts="${_host_ca_maven_opts} -Djavax.net.ssl.trustStoreType=PKCS12"
    # The store contains only public certificates; this is an integrity password, not a secret.
    _host_ca_maven_opts="${_host_ca_maven_opts} -Djavax.net.ssl.trustStorePassword=changeit"
    export MAVEN_OPTS="${_host_ca_maven_opts}"
    unset _host_ca_maven_opts
fi
