# Defines `derive_velox_target_cpu_flags()`, which computes the plugin's target-CPU compiler flags
# the same way the Presto worker's own build computes the worker's. The worker only loads a plugin
# built with matching flags, so the caller appends the result to `CMAKE_CXX_FLAGS`.
#
# What it does, in short:
#
# - On x86_64, defaults to the "avx" flag set the official presto-native images are built with.
# - On arm, defaults to the portable armv8-a "common" baseline the official presto-native arm
#   images (published from 0.299 onward) are built with.
# - The `CPU_TARGET` and `ARM_BUILD_TARGET` environment variables override the selection — see
#   "Target-CPU flags" in tools/build-packages/README.md for the accepted values.
# - Fails the configure on an unsupported selection, and logs the resolved flags otherwise.
#
# Provenance:
#
# - The heavy lifting is done by `get_cxx_flags`, a bash function from Velox that maps a CPU-target
#   keyword (e.g. "avx") to compiler flags. This module doesn't ship a copy of it — the caller
#   passes in the script that defines it via `<helper-script>`. At the pinned Presto commit's Velox
#   submodule, the function is:
#   https://github.com/facebookincubator/velox/blob/0dbf1731fb6e03ae615a40cda8c9b33f7bfb3490/scripts/setup-helper-functions.sh#L91-L187
#
# - The CMake code wrapping it is adapted from how upstream's own build invokes the same function,
#   near the top of `presto-native-execution/CMakeLists.txt`:
#   https://github.com/prestodb/presto/blob/6e1942b72a9f32191dcd0ba49812f2ac96a25615/presto-native-execution/CMakeLists.txt#L20-L31
#
# Upstream deviations — where this file intentionally differs from upstream's block, and why. The
# numbers match the `Deviation N` markers in the code below:
#
# 1. x86_64 defaults to "avx". Upstream's default lives in `presto-native-execution/Makefile`
#    (`CPU_TARGET ?= "avx"`), which this build doesn't go through:
#    https://github.com/prestodb/presto/blob/6e1942b72a9f32191dcd0ba49812f2ac96a25615/presto-native-execution/Makefile#L20
#    Without the default, `get_cxx_flags` would auto-detect the build machine's CPU, and a machine
#    without AVX would silently produce an sse-only plugin that official presto-native images
#    reject.
#
# 2. Arm pins ARM_BUILD_TARGET to the portable "common" baseline instead of upstream's default
#    "local" (tune for the build machine's arm core, baking in that core's extensions). Default
#    arm builds thereby work with the official presto-native arm images (published from 0.299
#    onward, built with the common baseline) and run on any armv8-a machine. Set
#    ARM_BUILD_TARGET=local to opt back in when building for the deployment machine's own core.
#
# 3. The values are passed to bash as positional arguments — upstream interpolates them into the
#    `bash -c` string — so the shell never interprets them.
#
# 4. An unsupported selection fails the configure. `get_cxx_flags` reports it as text with a zero
#    exit status, and upstream lets that text reach the compiler command line.
#
# NOTE: The permalinks point at the Presto commit pinned in taskfiles/velox-connector/deps.yaml
# (and its Velox submodule at that commit); refresh them when bumping the pin.

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

    # Deviation 3: pass the values as positional arguments (see header).
    execute_process(
        COMMAND bash -c
            "export ARM_BUILD_TARGET=\"$1\" && source \"$2\" && get_cxx_flags \"$3\""
            bash
            "${ARM_BUILD_TARGET}"
            "${HELPER_SCRIPT}"
            "${CPU_TARGET}"
        OUTPUT_VARIABLE VELOX_TARGET_CPU_CXX_FLAGS
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )

    # Deviation 4: catch the helper's zero-exit-status error text (see header). Real flags always
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
