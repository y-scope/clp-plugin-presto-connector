# Tools

Utilities that support building, packaging, and maintaining this repository.
All are invoked through `task` targets or CI workflows, though the scripts can
also be run directly.

## `build-packages/`

Builds installable `.deb`, `.rpm`, and `.tar.gz` artifacts for the connector
inside a hash-tagged build-env container image, so local and CI builds share
one reproducible environment. Used by `task package` and the `build-packages` /
`build-dependency-image` CI workflows. See its
[README](build-packages/README.md) for details.

## `presto-deps/`

Keeps the connector in lockstep with the Presto commit pinned by
`G_PRESTO_GIT_TAG` in
[taskfiles/velox-connector/deps.yaml](../taskfiles/velox-connector/deps.yaml),
since that commit (not a published release) is what both connectors are built
against.

* `validate-presto-dep-sync.py` — Checks that the version pins in
  `presto-connector/pom.xml` and the Velox dependency pins in `deps.yaml` match
  the pinned Presto commit and its Velox tree. Prints a suggested value for
  each mismatch and fails; it never edits anything. Runs before the
  `presto-connector` and `velox-connector` builds (as task dependencies), in
  the packaging container, and in the `validate-deps` CI workflow.
* `install-presto-artifacts.sh` — Source-builds the pinned Presto commit's
  Maven artifacts into the local Maven repository when the pin is unpublished
  (a fork URL or a suffixed version such as `0.299-SNAPSHOT`); official
  releases resolve from Maven Central instead. Provisions only the jars the
  Java coordinator plugin compiles against — the C++ worker plugin's
  Presto/Velox headers come from CMake `FetchContent`, not from here.
  Installs the `provided`-scope modules by default; `--with-test-deps` adds
  the `test`-scope closure. Stamp-gated: a no-op until the pin moves, the
  Maven repository changes, or `--force` is passed. Runs before
  `task presto-connector:build` / `test` and in the packaging container.

## `yscope-dev-utils/`

Git submodule of
[y-scope/yscope-dev-utils](https://github.com/y-scope/yscope-dev-utils), the
shared y-scope developer tooling (lint configs and reusable taskfiles).
Consumed by `taskfile.yaml`, `taskfiles/lint.yaml`, and the CI workflows.
