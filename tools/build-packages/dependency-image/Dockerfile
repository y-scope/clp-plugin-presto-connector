# syntax=docker/dockerfile:1
#
# Build-env image for CLP Presto connector packages.
# Installs packaging tools and connector C/C++ dependencies.

FROM quay.io/pypa/manylinux_2_28:latest

ARG HOST_CA_BUNDLE=/run/secrets/host-ca
ARG HOST_CA_ENV=/usr/local/share/clp-plugin-presto-connector/use-host-ca.sh

# When available, expose the host CA bundle only to networked build steps via
# tool-specific environment variables. This supports local corporate builds
# without baking host CA certificates into the final image.
COPY tools/build-packages/dependency-image/use-host-ca.sh ${HOST_CA_ENV}

# Install OS packages missing from the manylinux base image.
# dnf talks to libcurl directly and ignores CURL_CA_BUNDLE/SSL_CERT_FILE, so
# it needs its own --setopt=sslcacert pointed at the host CA bundle.
RUN --mount=type=bind,from=host-ca,source=host-ca,target=${HOST_CA_BUNDLE} \
    . "${HOST_CA_ENV}" \
 && dnf_sslcacert_opt="" \
 && if [ -s "${HOST_CA_BUNDLE}" ]; then \
        dnf_sslcacert_opt="--setopt=sslcacert=${HOST_CA_BUNDLE}"; \
    fi \
 && dnf install -y --setopt=install_weak_deps=False ${dnf_sslcacert_opt} \
        dpkg gettext git java-17-openjdk-devel libcurl-devel libevent-devel \
        libunwind-devel ninja-build openssl-devel patchelf python3-pip rpm-build \
 && dnf clean all

# Pin CMake below 4.0 for current CLP dependency builds. Pin a recent pip so
# it selects the pre-built CMake wheel instead of the source tarball.
RUN --mount=type=bind,from=host-ca,source=host-ca,target=${HOST_CA_BUNDLE} \
    . "${HOST_CA_ENV}" \
 && python3 -m pip install --no-cache-dir 'pip==21.3.1' \
 && python3 -m pip install --no-cache-dir 'cmake==3.28.*'

ARG GO_TASK_VERSION=v3.48.0
ARG TARGETARCH
RUN --mount=type=bind,from=host-ca,source=host-ca,target=${HOST_CA_BUNDLE} \
    set -euxo pipefail; \
    . "${HOST_CA_ENV}"; \
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
    --mount=type=bind,from=host-ca,source=host-ca,target=${HOST_CA_BUNDLE} \
    . "${HOST_CA_ENV}" \
 && TASK_CONCURRENCY=1 task -d /repo velox-connector:deps:install-all
