# syntax=docker/dockerfile:1
#
# Build environment for clp-plugin-presto-connector.
#
# manylinux_2_28 base (glibc 2.28 ABI floor), velox's setup-manylinux.sh to
# build Folly / fbthrift / Arrow / etc. into /usr/local, then the rest of
# what tools/build-packages/build.sh needs on top (JDK 17, go-task,
# dpkg/rpm-build/patchelf). Each RUN below documents what it does and why.
#
# velox source is supplied via `--build-context velox-scripts=<velox-clone>/scripts`
# so the COPY layers pull from the exact velox SHA pinned by prestodb/presto's
# submodule (see .github/workflows/build-dependency-image.yaml).
#
# Built and published by .github/workflows/build-dependency-image.yaml.
# Consumed by tools/build-packages/build.sh.

FROM quay.io/pypa/manylinux_2_28:latest

# Host CA bundle for corporate TLS-intercepting proxies (e.g. Zscaler).
# Staged into the build context by lib.sh's build_image() — empty file = no
# install (the common case; CI runners have no corporate proxy).
COPY ca-certificates.crt /tmp/host-ca.crt
RUN if [ -s /tmp/host-ca.crt ]; then \
        cp /tmp/host-ca.crt /etc/pki/ca-trust/source/anchors/host-ca-bundle.crt \
            && update-ca-trust extract; \
    fi \
 && rm -f /tmp/host-ca.crt

# Point tools that don't read the system trust store at the system bundle
# (which now includes the host CA if one was installed above).
ENV CURL_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt \
    SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt \
    REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt \
    PIP_CERT=/etc/pki/tls/certs/ca-bundle.crt

# velox setup scripts (from the pinned velox SHA).
COPY --from=velox-scripts setup-helper-functions.sh /
COPY --from=velox-scripts setup-versions.sh /
COPY --from=velox-scripts setup-common.sh /
COPY --from=velox-scripts setup-manylinux.sh /

# Install build prerequisites ourselves so we can use the AlmaLinux-8-correct
# repo name. setup-manylinux.sh's install_build_prerequisites runs
# `dnf config-manager --set-enabled crb`, but `crb` is an EL9-only repo
# (the equivalent on EL8 is `powertools`). We replicate the rest of the
# prereq install verbatim, then run setup-manylinux.sh with
# INSTALL_PREREQUISITES=N so it skips its own (EL9-only) prereq step and
# jumps straight to building deps from source.
RUN dnf update -y \
 && dnf install -y --setopt=install_weak_deps=False epel-release dnf-plugins-core \
 && dnf config-manager --set-enabled powertools \
 && dnf update -y \
 && dnf install -y --setopt=install_weak_deps=False \
        ninja-build cmake ccache gcc-toolset-12 git wget which \
        autoconf automake python3-devel python3-pip libtool \
 && dnf clean all

# Add /usr/local/{lib,lib64} to the dynamic linker search path BEFORE
# setup-manylinux.sh runs. Several deps (fbthrift in particular) build a
# code-generator binary linked against earlier-built deps (libgflags etc.)
# and then run it during their own build to generate sources — without
# this, those runs fail with "libgflags.so.2.2: cannot open shared object."
RUN echo "/usr/local/lib"   >  /etc/ld.so.conf.d/velox_deps.conf \
 && echo "/usr/local/lib64" >> /etc/ld.so.conf.d/velox_deps.conf \
 && ldconfig

# Build velox dependencies into /usr/local. ~2 hours.
#
# LD_LIBRARY_PATH scopes to this RUN only — fbthrift's build invokes the
# thrift1 codegen binary it just compiled, which dynamically links against
# libgflags.so.2.2 installed by the preceding install_gflags step. We
# haven't re-run ldconfig yet so the cache doesn't know about it; the env
# var makes the loader search /usr/local/lib directly during this build.
# The trailing `ldconfig` updates the cache for downstream users.
RUN INSTALL_PREREQUISITES=N \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64 \
    bash /setup-manylinux.sh \
 && ldconfig

# xsimd is header-only and intentionally omitted from velox's install_velox_deps
# (velox normally FetchContents it during its own build via
# CMake/resolve_dependency_modules/xsimd.cmake). The plugin consumes velox
# headers directly (SimdUtil.h includes <xsimd/xsimd.hpp>) without running
# velox's CMake, so we install xsimd into /usr/local explicitly by invoking
# the dedicated function from setup-common.sh.
RUN bash /setup-manylinux.sh install_xsimd

# Velox's deps were compiled with gcc-toolset-12 (installed by setup-manylinux.sh).
# Use the same toolset for the plugin to avoid C++ ABI mismatches.
ENV CC=/opt/rh/gcc-toolset-12/root/usr/bin/gcc \
    CXX=/opt/rh/gcc-toolset-12/root/usr/bin/g++ \
    PATH=/opt/rh/gcc-toolset-12/root/usr/bin:${PATH}

# JDK 17 (Maven), gettext (envsubst), dpkg/rpm-build/patchelf (packaging).
RUN dnf install -y java-17-openjdk-devel dpkg gettext patchelf rpm-build \
 && dnf clean all \
 && ln -s "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" \
          /usr/lib/jvm/java-17-default
ENV JAVA_HOME=/usr/lib/jvm/java-17-default

# go-task — cmake driver invoked by build.sh.
ARG GO_TASK_VERSION=v3.48.0
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64)  task_arch=amd64 ;; \
        aarch64) task_arch=arm64 ;; \
    esac; \
    mkdir -p /opt/go-task/bin; \
    curl -fsSL "https://github.com/go-task/task/releases/download/${GO_TASK_VERSION}/task_linux_${task_arch}.tar.gz" \
        | tar xz -C /opt/go-task/bin task

ENV PATH=/opt/go-task/bin:${JAVA_HOME}/bin:${PATH}

# Marker checked by tools/build-packages/build.sh to refuse to run outside
# this image.
ENV CLP_PLUGIN_BUILD_ENV=1
