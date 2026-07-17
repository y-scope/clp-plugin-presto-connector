# Build cache

Host and container helpers for persistent build caches. They fix cache layout and tool configuration; the caller controls cache location, identity, and mounting.

## Layout

Given a cache directory and key:

```text
<cache-directory>/
├── build/<cache-key>/
├── ccache/
├── fetchcontent/<cache-key>/
└── maven/
```

Maven and ccache are shared across keys. The project build and FetchContent hold generated state and are isolated by a caller-provided key, such as a build-env hash.

## Host API

```bash
source tools/build-packages/internal/build-cache/host.sh
prepare_build_cache ./.cache "${build_env_hash}"
```

The cache key must be nonempty and safe as a path component.

## Container API

```bash
BUILD_CACHE_DIR=/var/cache/build
BUILD_CACHE_KEY="${build_env_hash}"
source tools/build-packages/internal/build-cache/container.sh
```

Creates missing subdirectories and exports defaults for ccache, Maven, CMake compiler launchers, and `FETCHCONTENT_BASE_DIR`; existing env vars take precedence. Projects must pass `FETCHCONTENT_BASE_DIR` to CMake themselves — the helper only exports it.

## Lifecycle

Caches are persistent (sources, objects, generated state) and are not removed automatically; the caller decides when to delete or rotate them.