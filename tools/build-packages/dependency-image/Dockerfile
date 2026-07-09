# syntax=docker/dockerfile:1
#
# Build-env image for CLP Presto connector packages.
# Installs packaging tools and connector C/C++ dependencies.

FROM quay.io/pypa/manylinux_2_28:latest

# When available, expose the host CA bundle only to networked build steps via
# tool-specific environment variables. This supports local corporate builds
# without baking host CA certificates into the final image.

# Install OS packages missing from the manylinux base image.
RUN --mount=type=secret,id=host-ca \
    if [ -s /run/secrets/host-ca ]; then \
        export CURL_CA_BUNDLE=/run/secrets/host-ca \
            GIT_SSL_CAINFO=/run/secrets/host-ca \
            PIP_CERT=/run/secrets/host-ca \
            REQUESTS_CA_BUNDLE=/run/secrets/host-ca \
            SSL_CERT_FILE=/run/secrets/host-ca; \
    fi \
 && dnf install -y --setopt=install_weak_deps=False \
        dpkg gettext git java-17-openjdk-devel libcurl-devel libevent-devel \
        libunwind-devel ninja-build openssl-devel patchelf python3-pip rpm-build \
 && dnf clean all

# Pin CMake below 4.0 for current CLP dependency builds. Pin a recent pip so
# it selects the pre-built CMake wheel instead of the source tarball.
RUN --mount=type=secret,id=host-ca \
    if [ -s /run/secrets/host-ca ]; then \
        export CURL_CA_BUNDLE=/run/secrets/host-ca \
            GIT_SSL_CAINFO=/run/secrets/host-ca \
            PIP_CERT=/run/secrets/host-ca \
            REQUESTS_CA_BUNDLE=/run/secrets/host-ca \
            SSL_CERT_FILE=/run/secrets/host-ca; \
    fi \
 && python3 -m pip install --no-cache-dir 'pip==21.3.1' \
 && python3 -m pip install --no-cache-dir 'cmake==3.28.*'

# go-task — task driver for dependency installation and CMake builds.
ARG GO_TASK_VERSION=v3.48.0
ARG TARGETARCH
RUN --mount=type=secret,id=host-ca \
    set -eux; \
    if [ -s /run/secrets/host-ca ]; then \
        export CURL_CA_BUNDLE=/run/secrets/host-ca \
            GIT_SSL_CAINFO=/run/secrets/host-ca \
            PIP_CERT=/run/secrets/host-ca \
            REQUESTS_CA_BUNDLE=/run/secrets/host-ca \
            SSL_CERT_FILE=/run/secrets/host-ca; \
    fi; \
    mkdir -p /opt/go-task/bin; \
    curl -fsSL "https://github.com/go-task/task/releases/download/${GO_TASK_VERSION}/task_linux_${TARGETARCH}.tar.gz" \
        | tar xz -C /opt/go-task/bin task

ENV PATH=/opt/go-task/bin:${PATH}

ENV CLP_PLUGIN_BUILD_DIR=/opt/clp-plugin-presto-connector/build
ENV TASK_TEMP_DIR=/opt/clp-plugin-presto-connector/.task

# Build one dependency at a time; each dependency build still defaults to nproc.
# Bind-mount the repository as readonly build input. Dependency outputs and Task
# checksum metadata are written outside the repository mount so package builds
# can reuse the installed dependencies from the image.
RUN --mount=type=bind,source=.,target=/repo,readonly \
    --mount=type=secret,id=host-ca \
    if [ -s /run/secrets/host-ca ]; then \
        export CURL_CA_BUNDLE=/run/secrets/host-ca \
            GIT_SSL_CAINFO=/run/secrets/host-ca \
            PIP_CERT=/run/secrets/host-ca \
            REQUESTS_CA_BUNDLE=/run/secrets/host-ca \
            SSL_CERT_FILE=/run/secrets/host-ca; \
    fi \
 && TASK_CONCURRENCY=1 task -d /repo velox-connector:deps:install-all
