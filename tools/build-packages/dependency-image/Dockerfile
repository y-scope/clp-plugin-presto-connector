# syntax=docker/dockerfile:1
#
# Build environment for clp-plugin-presto-connector.
#
# manylinux_2_28 base (glibc 2.28 ABI floor), velox's setup-manylinux.sh to
# build Folly / fbthrift / Arrow / etc. into /usr/local, then the rest of
# what tools/build-packages/build.sh needs on top (JDK 17, go-task,
# dpkg/rpm-build/patchelf). Each RUN below documents what it does and why.
#
# velox setup scripts are downloaded directly from raw.githubusercontent.com
# at the SHA passed via --build-arg VELOX_SHA. lib.sh::derive_velox_sha
# resolves that SHA from the presto pin in velox-connector/CMakeLists.txt
# via GitHub's contents API (no clone, no submodule).
#
# Built and published by .github/workflows/build-dependency-image.yaml.
# Consumed by tools/build-packages/build.sh.

FROM quay.io/pypa/manylinux_2_28:latest

# Velox SHA to pin the setup-*.sh scripts to. Supplied by lib.sh::build_image
# (which gets it from derive_velox_sha → GitHub contents API).
ARG VELOX_SHA

# Host CA bundle for corporate TLS-intercepting proxies (e.g. Zscaler).
# Mounted ephemerally via `--secret` by lib.sh's build_image() — empty file = no
# install (the common case; CI runners have no corporate proxy). The bundle
# bytes never enter the image; only the trust-store mutation persists.
COPY --from=ca-bundle install-ca-bundle.sh /tmp/install-ca-bundle.sh
RUN --mount=type=secret,id=host-ca \
    if [ -s /run/secrets/host-ca ]; then \
        bash /tmp/install-ca-bundle.sh /run/secrets/host-ca; \
    fi \
 && rm -f /tmp/install-ca-bundle.sh

# Point tools that don't read the system trust store at the system bundle
# (which now includes the host CA if one was installed above).
ENV CURL_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt \
    SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt \
    REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt \
    PIP_CERT=/etc/pki/tls/certs/ca-bundle.crt

# velox setup scripts at the pinned velox SHA. Fetched via raw.githubusercontent.com
# so we don't need to clone presto or velox on the host. The four files cover everything
# setup-manylinux.sh sources (it sources setup-common.sh which sources setup-versions.sh
# and setup-helper-functions.sh).
RUN test -n "${VELOX_SHA}" || { echo "ERROR: --build-arg VELOX_SHA is required" >&2; exit 1; } \
 && for f in setup-helper-functions.sh setup-versions.sh setup-common.sh setup-manylinux.sh; do \
        curl -fsSL "https://raw.githubusercontent.com/facebookincubator/velox/${VELOX_SHA}/scripts/${f}" \
             -o "/${f}"; \
    done

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

# Use gcc-toolset-14 (the manylinux_2_28 base image's default GCC). The base ships an
# /etc/profile.d/scl-init.sh that prepends it to PATH for login shells, but build.sh and
# cmake run in non-login shells, so we re-export the PATH here. No explicit CC/CXX env —
# cmake auto-detects from PATH. (Velox's setup-manylinux.sh above pins gcc-toolset-12 for
# building velox's own /usr/local libs; the plugin links against those statically and the
# 12→14 libstdc++ ABI is forward-compatible.)
ENV PATH=/opt/rh/gcc-toolset-14/root/usr/bin:${PATH}

# Pin CMake to 3.28 (latest 3.x the manylinux base's pip can resolve; overrides the base's
# 4.x at /usr/bin/cmake via PATH order: pip drops it at /usr/local/bin which is ahead of
# /usr/bin). CMake 4.x removed support for `cmake_minimum_required(VERSION < 3.5)`, which
# trips a number of CLP's transitive dep tarballs (yaml-cpp 0.7.0, antlr-runtime's bundled
# googletest, ...). Sticking to a 3.x line side-steps that en masse instead of patching
# each upstream.
RUN python3 -m pip install --no-cache-dir --upgrade pip \
 && python3 -m pip install --no-cache-dir 'cmake==3.28.*'

# Hide velox's /usr/local/lib64/libsnappy.a from mongo-c-driver.
#
# Velox's setup-manylinux.sh above installs libsnappy.a (C++) into /usr/local/lib64 for
# Velox's own use. mongo-c-driver (built later as a transitive dep of CLP's mongocxx) ships
# a FindSnappy.cmake that opportunistically scans /usr/local/lib — it finds Velox's archive
# and statically embeds snappy into libmongoc2.so. That .so then has unresolved C++ symbols
# (std::__throw_bad_array_new_length etc.) with no libstdc++ in its DT_NEEDED, because
# mongo-c-driver declares LANGUAGES C and doesn't add libstdc++ when linking its C
# executables (mongoc2-stat). The link then fails with --no-undefined-style errors.
#
# CLP's own CI doesn't hit this because their image has no /usr/local/lib64/libsnappy.a —
# mongo-c-driver builds without snappy compression and the chain stays C-only.
#
# Fix: pre-poison FindSnappy's cache vars with the *-NOTFOUND convention. CMake's
# find_path/find_library skip the search when the cache var is already set, so FindSnappy
# reports "not found", mongo-c-driver's `if(SNAPPY_INCLUDE_DIRS)` block stays dead, snappy
# is never embedded, no C++ symbols leak. The plugin doesn't use mongocxx, so disabling
# snappy compression there costs nothing.
#
# Delivery mechanism: CMAKE_TOOLCHAIN_FILE env is read by every cmake configure and is
# automatically propagated by FetchContent into nested sub-builds. We don't set
# CMAKE_SYSTEM_NAME, so this doesn't trigger cross-compile mode — it's purely a hook for
# image-wide cache overrides.
RUN mkdir -p /etc/cmake \
 && printf '%s\n' \
        '# Loaded via CMAKE_TOOLCHAIN_FILE env on every cmake configure in this image.' \
        '# See tools/build-packages/dependency-image/Dockerfile for the rationale.' \
        '' \
        '# (1) Disable snappy support in mongo-c-driver so it does not embed velox-built' \
        '# /usr/local/lib64/libsnappy.a (C++) into libmongoc2.so. Plugin does not use' \
        '# mongocxx, so this costs nothing. Without this, libmongoc2.so picks up' \
        '# unresolved C++ symbols and mongoc-stat (a C exe) fails to link.' \
        'set(ENABLE_SNAPPY "OFF" CACHE STRING "Disabled to avoid /usr/local/lib64 snappy" FORCE)' \
        '' \
        '# (2) Force -fPIC for every static lib built by CLP deps. CLP optimizes for its own' \
        '# executable targets and leaves PIC off (e.g. antlr-runtime, log-surgeon). The plugin' \
        '# is a shared lib, so every static dep it links must be PIC or the .so link fails' \
        '# with R_AARCH64_ADR_PREL_PG_HI21 / R_X86_64_PC32 relocation errors.' \
        'set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Plugin .so requires PIC deps" FORCE)' \
    > /etc/cmake/clp-plugin-overrides.cmake
ENV CMAKE_TOOLCHAIN_FILE=/etc/cmake/clp-plugin-overrides.cmake

# Boost (b2) doesn't read CMAKE_POSITION_INDEPENDENT_CODE or CXXFLAGS env. Inject -fPIC
# via its own config mechanism: b2 auto-reads $HOME/user-config.jam on every invocation.
# Same rationale as (2) above — the plugin .so needs every static boost lib to be PIC.
RUN echo "using gcc : : : <cxxflags>-fPIC <cflags>-fPIC ;" > /root/user-config.jam

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
