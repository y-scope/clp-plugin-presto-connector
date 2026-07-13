# Build cache

This directory provides reusable host and container helpers for persistent build caches. The helpers keep cache layout and tool configuration consistent while leaving cache location, cache identity, and container mounting under the caller's control.

## Layout

Given a cache directory and key, the helpers use:

```text
<cache-directory>/
├── ccache/
├── fetchcontent/<cache-key>/
└── maven/
```

Maven and ccache content is shared across cache keys. FetchContent contains generated CMake state and is isolated by a caller-provided key, such as a build-environment hash.

## Host API

Source `host.sh`, then prepare the cache before mounting it:

```bash
source tools/build-packages/internal/build-cache/host.sh
prepare_build_cache ./.cache "${build_env_hash}"
```

The caller is responsible for choosing a nonempty cache key that is safe to use as a path component.

## Container API

Mount the prepared cache, set its container path and key, then source `container.sh`:

```bash
BUILD_CACHE_DIR=/var/cache/build
BUILD_CACHE_KEY="${build_env_hash}"
source tools/build-packages/internal/build-cache/container.sh
```

The container helper creates missing subdirectories and supplies defaults for Maven, ccache, CMake compiler launchers, and `FETCHCONTENT_BASE_DIR`. Existing tool-specific environment variables take precedence over those defaults.

`FETCHCONTENT_BASE_DIR` is an integration variable: projects must pass it to CMake as `-DFETCHCONTENT_BASE_DIR=...`. The helper does not modify project CMake files or command lines.

## Lifecycle

Build caches are persistent and may contain downloaded source, compiled objects, and generated build state. They are not temporary staging material and are not removed automatically. The caller decides when to delete or rotate the cache.
