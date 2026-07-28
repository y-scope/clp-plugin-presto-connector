# Defines `derive_velox_target_cpu_flags()`, which computes the plugin's target-CPU compiler flags
# the same way the Presto worker's own build computes the worker's. A worker only loads a plugin
# built with matching flags, so the caller appends the result to `CMAKE_CXX_FLAGS`.
#
# Behavior:
# - The `CPU_TARGET`/`ARM_BUILD_TARGET` environment variables select the target, as upstream (for
#   the accepted values, see "Target-CPU flags" in tools/build-packages/README.md).
# - When unset, they default to what the official presto-native docker images are built with:
#   "avx" on x86_64, and the portable armv8-a "common" baseline on arm (images from 0.299 onward).
# - An unsupported selection fails the configure; otherwise the resolved flags are logged.
#
# The keyword-to-flags mapping is Velox's `get_cxx_flags` bash function, which the caller passes
# in via `<helper-script>` — this module doesn't ship a copy. The CMake wrapper around it is
# adapted from upstream's own invocation. Both at the pinned Presto commit (refresh the permalinks
# when bumping the pin in taskfiles/velox-connector/deps.yaml):
# - https://github.com/facebookincubator/velox/blob/0dbf1731fb6e03ae615a40cda8c9b33f7bfb3490/scripts/setup-helper-functions.sh#L91-L187
# - https://github.com/prestodb/presto/blob/6e1942b72a9f32191dcd0ba49812f2ac96a25615/presto-native-execution/CMakeLists.txt#L20-L31
#
# Deviations from upstream's invocation (numbers match the `Deviation N` markers below). 1 and 2
# exist so an unconfigured build matches the official images rather than the build machine — the
# build machine's CPU says nothing about the worker that will load the plugin:
#
# 1. Default CPU_TARGET to "avx" on x86_64 here in CMake. Upstream's identical default lives in
#    their Makefile (`CPU_TARGET ?= "avx"`), which this build never runs. Without it,
#    auto-detection on a non-AVX build machine would pick "sse", and official (avx) workers would
#    refuse to load the plugin — with no hint at build time.
# 2. Default ARM_BUILD_TARGET to "common" instead of upstream's "local" (tune for the build
#    machine's arm core). "common" matches the official arm images and runs on any armv8-a
#    machine; ARM_BUILD_TARGET=local opts back in.
# 3. Fail the configure on an unsupported selection: `get_cxx_flags` reports one as text with a
#    zero exit status, which upstream lets reach the compiler command line.

# derive_velox_target_cpu_flags(<output-variable> <helper-script>)
#
# Arguments:
# - output-variable: name of the variable to store the derived flags in, set in the caller's
#   scope.
# - helper-script: path to Velox's `scripts/setup-helper-functions.sh`, which provides
#   `get_cxx_flags`.
function(derive_velox_target_cpu_flags OUTPUT_VARIABLE HELPER_SCRIPT)
    # Empty means "let get_cxx_flags auto-detect the build machine's CPU".
    set(CPU_TARGET "$ENV{CPU_TARGET}")

    # Deviation 1: default x86_64 to "avx" (see header).
    if(CPU_TARGET STREQUAL "" AND CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64")
        set(CPU_TARGET "avx")
    endif()

    # Deviation 2: pin the portable "common" arm baseline (see header).
    set(ARM_BUILD_TARGET "$ENV{ARM_BUILD_TARGET}")
    if(ARM_BUILD_TARGET STREQUAL "")
        set(ARM_BUILD_TARGET "common")
    endif()

    execute_process(
        COMMAND bash -c
            "export ARM_BUILD_TARGET=${ARM_BUILD_TARGET} && source ${HELPER_SCRIPT} && get_cxx_flags ${CPU_TARGET}"
        OUTPUT_VARIABLE VELOX_TARGET_CPU_CXX_FLAGS
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )

    # Deviation 3: catch the helper's zero-exit-status error text (see header). Real flags always
    # start with "-".
    if(NOT VELOX_TARGET_CPU_CXX_FLAGS MATCHES "^-")
        message(FATAL_ERROR
            "get_cxx_flags rejected CPU_TARGET='${CPU_TARGET}':"
            " ${VELOX_TARGET_CPU_CXX_FLAGS} Valid values: avx, sse (x86_64), aarch64, arm64"
            " (Apple Silicon), or unset for the default (avx on x86_64, matching official"
            " presto-native builds; auto-detected elsewhere)."
        )
    endif()

    message(STATUS "Target-CPU flags (get_cxx_flags): ${VELOX_TARGET_CPU_CXX_FLAGS}")
    set("${OUTPUT_VARIABLE}" "${VELOX_TARGET_CPU_CXX_FLAGS}" PARENT_SCOPE)
endfunction()
