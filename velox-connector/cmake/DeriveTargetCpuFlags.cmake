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
# - Everywhere this file intentionally differs from upstream's version, the difference is marked
#   with an "Upstream deviation:" comment explaining why.
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
    set(CPU_TARGET "$ENV{CPU_TARGET}")
    if(CPU_TARGET STREQUAL "" AND CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64")
        # Upstream deviation: default to "avx" to match Presto's official native builds.
        # Upstream's default comes from `CPU_TARGET ?= "avx"` in `presto-native-execution/Makefile`:
        # https://github.com/prestodb/presto/blob/6e1942b72a9f32191dcd0ba49812f2ac96a25615/presto-native-execution/Makefile#L20
        # This build doesn't go through that Makefile; without the default here, `get_cxx_flags`
        # would auto-detect the build machine's CPU, and a machine without AVX would silently
        # produce an sse-only plugin that official presto-native images reject.
        set(CPU_TARGET "avx")
    endif()
    # Upstream deviation: `get_cxx_flags` defaults ARM_BUILD_TARGET to "local", tuning for the
    # build machine's arm core and baking that core's extensions into the plugin. Pin its portable
    # "common" mode instead so that a default arm build works with the official presto-native arm
    # docker images — published from 0.299 onward and built with the common baseline — and runs on
    # any armv8-a machine. ARM_BUILD_TARGET=local opts back in for builds that target the build
    # machine's own core.
    set(ARM_BUILD_TARGET "$ENV{ARM_BUILD_TARGET}")
    if(ARM_BUILD_TARGET STREQUAL "")
        set(ARM_BUILD_TARGET "common")
    endif()
    # Upstream deviation: pass the values as positional arguments (upstream interpolates them into
    # the `bash -c` string) so the shell never interprets them.
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
    # Upstream deviation: `get_cxx_flags` reports an unsupported selection as text with a zero exit
    # status; catch it here rather than letting it reach the compiler command line as upstream
    # does.
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
