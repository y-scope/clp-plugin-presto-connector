# syntax=docker/dockerfile:1
#
# Build-env image for CLP Presto connector packages.
# Installs packaging tools and connector C/C++ dependencies.

FROM quay.io/pypa/manylinux_2_28:latest

# Install an optional host CA bundle without copying the bundle into an image layer.
COPY tools/ca-bundle/install-ca-bundle.sh /tmp/install-ca-bundle.sh
RUN --mount=type=secret,id=host-ca \
    if [ -s /run/secrets/host-ca ]; then \
        bash /tmp/install-ca-bundle.sh /run/secrets/host-ca; \
    fi \
 && rm -f /tmp/install-ca-bundle.sh

# Use the system CA bundle for tools that don't read the system trust store.
ENV CURL_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt \
    SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt \
    REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt \
    PIP_CERT=/etc/pki/tls/certs/ca-bundle.crt

# Install OS packages missing from the manylinux base image.
RUN dnf install -y --setopt=install_weak_deps=False \
        dpkg gettext git java-17-openjdk-devel libcurl-devel libevent-devel \
        libunwind-devel ninja-build openssl-devel patchelf python3-pip rpm-build \
 && dnf clean all

# Pin CMake below 4.0 for current CLP dependency builds.
RUN python3 -m pip install --no-cache-dir --upgrade pip \
 && python3 -m pip install --no-cache-dir 'cmake==3.28.*'

# go-task — task driver for dependency installation and CMake builds.
ARG GO_TASK_VERSION=v3.48.0
ARG TARGETARCH
RUN set -eux; \
    mkdir -p /opt/go-task/bin; \
    curl -fsSL "https://github.com/go-task/task/releases/download/${GO_TASK_VERSION}/task_linux_${TARGETARCH}.tar.gz" \
        | tar xz -C /opt/go-task/bin task

ENV PATH=/opt/go-task/bin:${PATH}

ENV CLP_PLUGIN_BUILD_DIR=/opt/clp-plugin-presto-connector/build
WORKDIR /opt/clp-plugin-presto-connector
RUN mkdir -p tools

# Build one dependency at a time; each dependency build still defaults to nproc.
RUN --mount=type=bind,source=taskfile.yaml,target=/opt/clp-plugin-presto-connector/taskfile.yaml,readonly \
    --mount=type=bind,source=taskfiles,target=/opt/clp-plugin-presto-connector/taskfiles,readonly \
    --mount=type=bind,source=tools/yscope-dev-utils,target=/opt/clp-plugin-presto-connector/tools/yscope-dev-utils,readonly \
    TASK_CONCURRENCY=1 task velox-connector:deps:install-all

# Marker for scripts to verify they are running in the dependency image.
ENV CLP_PLUGIN_BUILD_ENV=1
