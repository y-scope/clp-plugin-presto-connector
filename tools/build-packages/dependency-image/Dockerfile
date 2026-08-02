# syntax=docker/dockerfile:1

# Empty default for the `ca_trust` build context, so networked RUN steps below
# resolve their mount when no host CA trust is supplied. `build_image` overrides
# this stage with a staged directory when --with-ca-certs is passed; without it
# the mount is empty, the guard falls through, and the image keeps its own
# distro trust store. See yscope-dev-utils exports/docker/ca-trust.
FROM scratch AS ca_trust

FROM quay.io/pypa/manylinux_2_28:latest

# NOTE: these duplicate the ca-trust library's CA_TRUST_CONTAINER_DIR and
# CA_TRUST_BUNDLE_FILENAME, which a Dockerfile can't read; keep them in sync.
# container.sh is sourced directly rather than via container-exec.sh because this
# base image's /bin/sh is bash. A base without that (Debian, Alpine) must switch to
# `bash /run/ca-trust/container-exec.sh <cmd>`.
# Where the ca_trust context is mounted during networked RUN steps. Declared as
# an ARG so container.sh finds the staged bundle; nothing is baked into the
# image and the mount disappears with the step.
ARG CA_TRUST_DIR=/run/ca-trust
ARG CA_TRUST_BUNDLE=/run/ca-trust/ca-bundle.pem

# Install OS packages missing from the manylinux base image.
# dnf talks to libcurl directly and ignores CURL_CA_BUNDLE/SSL_CERT_FILE, so
# it needs its own --setopt=sslcacert pointed at the host CA bundle.
RUN --mount=type=bind,from=ca_trust,target=/run/ca-trust \
    if [ -e /run/ca-trust/container.sh ]; then . /run/ca-trust/container.sh; fi \
 && dnf_sslcacert_opt="" \
 && if [ -s "${CA_TRUST_BUNDLE}" ]; then \
        dnf_sslcacert_opt="--setopt=sslcacert=${CA_TRUST_BUNDLE}"; \
    fi \
 && dnf install -y --setopt=install_weak_deps=False ${dnf_sslcacert_opt} \
        ccache dpkg gettext git java-17-openjdk-devel libcurl-devel libevent-devel \
        libunwind-devel ninja-build openssl-devel patchelf python3-pip rpm-build \
 && dnf clean all

RUN --mount=type=bind,from=ca_trust,target=/run/ca-trust \
    if [ -e /run/ca-trust/container.sh ]; then . /run/ca-trust/container.sh; fi \
 && python3 -m pip install --no-cache-dir 'pip==21.3.1' \
 && python3 -m pip install --no-cache-dir 'cmake==3.28.*'

ARG GO_TASK_VERSION=v3.48.0
ARG TARGETARCH
RUN --mount=type=bind,from=ca_trust,target=/run/ca-trust \
    set -euxo pipefail; \
    if [ -e /run/ca-trust/container.sh ]; then . /run/ca-trust/container.sh; fi; \
    mkdir -p /opt/go-task/bin; \
    curl -fsSL "https://github.com/go-task/task/releases/download/${GO_TASK_VERSION}/task_linux_${TARGETARCH}.tar.gz" \
        | tar xz -C /opt/go-task/bin task

ENV PATH=/opt/go-task/bin:${PATH}

ENV CLP_PLUGIN_BUILD_DIR=/opt/clp-plugin-presto-connector/build
ENV CLP_PLUGIN_DEPS_CPP_DIR=/opt/clp-plugin-presto-connector/build/velox-connector/deps/cpp
ENV TASK_TEMP_DIR=/opt/clp-plugin-presto-connector/.task

# Build one dependency at a time to avoid excessive memory usage from parallel builds.
RUN --mount=type=bind,source=.,target=/repo,readonly \
    --mount=type=bind,from=ca_trust,target=/run/ca-trust \
    if [ -e /run/ca-trust/container.sh ]; then . /run/ca-trust/container.sh; fi \
 && task --concurrency 1 -d /repo velox-connector:deps:install-all
