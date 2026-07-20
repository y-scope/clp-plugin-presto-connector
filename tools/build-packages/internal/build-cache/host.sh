#!/usr/bin/env bash

# Host-side preparation for persistent container build caches.

if [[ "${_BUILD_CACHE_HOST_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _BUILD_CACHE_HOST_SH_LOADED=1

# Creates the shared tool caches and a namespaced FetchContent cache.
#
# Args: <cache-directory> <cache-key>
prepare_build_cache() {
    if (( $# != 2 )) || [[ -z "$1" || -z "$2" ]]; then
        echo >&2 "ERROR: prepare_build_cache requires a cache directory and key"
        return 2
    fi

    local cache_dir="$1"
    local cache_key="$2"
    mkdir -p \
        "${cache_dir}/build/${cache_key}" \
        "${cache_dir}/ccache" \
        "${cache_dir}/fetchcontent/${cache_key}" \
        "${cache_dir}/maven"
}
