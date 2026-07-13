#!/usr/bin/env sh

# Container-side configuration for consuming a prepared build cache.

if [ -n "${BUILD_CACHE_DIR:-}" ]; then
    if [ -z "${BUILD_CACHE_KEY:-}" ]; then
        echo >&2 "ERROR: BUILD_CACHE_KEY must be set when BUILD_CACHE_DIR is set"
        return 1
    fi

    export CCACHE_DIR="${CCACHE_DIR:-${BUILD_CACHE_DIR}/ccache}"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-1G}"
    export CMAKE_C_COMPILER_LAUNCHER="${CMAKE_C_COMPILER_LAUNCHER:-ccache}"
    export CMAKE_CXX_COMPILER_LAUNCHER="${CMAKE_CXX_COMPILER_LAUNCHER:-ccache}"
    export FETCHCONTENT_BASE_DIR="${FETCHCONTENT_BASE_DIR:-${BUILD_CACHE_DIR}/fetchcontent/${BUILD_CACHE_KEY}}"
    export MAVEN_USER_HOME="${MAVEN_USER_HOME:-${BUILD_CACHE_DIR}/maven}"

    mkdir -p \
        "${CCACHE_DIR}" \
        "${FETCHCONTENT_BASE_DIR}" \
        "${MAVEN_USER_HOME}"
fi
