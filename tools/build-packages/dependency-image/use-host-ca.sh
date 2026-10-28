if [ -s "${HOST_CA_BUNDLE}" ]; then
    export CURL_CA_BUNDLE="${HOST_CA_BUNDLE}"
    export GIT_SSL_CAINFO="${HOST_CA_BUNDLE}"
    export PIP_CERT="${HOST_CA_BUNDLE}"
    export REQUESTS_CA_BUNDLE="${HOST_CA_BUNDLE}"
    export SSL_CERT_FILE="${HOST_CA_BUNDLE}"
fi
