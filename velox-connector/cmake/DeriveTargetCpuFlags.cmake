# Defines `derive_velox_target_cpu_flags()`, which derives the target-CPU compiler flags that the
# Presto worker's own build uses.
#
# The implementation is adapted from the `execute_process(... get_cxx_flags ...)` block near the
# top of upstream's `presto-native-execution/CMakeLists.txt`:
# https://github.com/prestodb/presto/blob/6e1942b72a9f32191dcd0ba49812f2ac96a25615/presto-native-execution/CMakeLists.txt#L20-L31
# `get_cxx_flags` is a bash function from Velox (`velox/scripts/setup-helper-functions.sh`) that
# maps a CPU-target keyword to compiler flags, so the flag selection always tracks the pinned
# Presto commit:
# https://github.com/facebookincubator/velox/blob/0dbf1731fb6e03ae615a40cda8c9b33f7bfb3490/scripts/setup-helper-functions.sh#L91-L187
# (The permalinks point at the Presto commit pinned in taskfiles/velox-connector/deps.yaml and its
# Velox submodule; refresh them when bumping the pin.) Deviations from upstream's block are
# commented inline.

# derive_velox_target_cpu_flags(<output-variable> <helper-script>)
#
# Runs `get_cxx_flags` from `<helper-script>` (the path to Velox's
# `scripts/setup-helper-functions.sh`) and stores the derived flags in `<output-variable>` in the
# caller's scope. The selection is controlled by the `CPU_TARGET`/`ARM_BUILD_TARGET` environment
# variables, as upstream (see "Target-CPU flags" in tools/build-packages/README.md). Fails the
# configure if the selection is unsupported.
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
    # Upstream deviation: `get_cxx_flags` defaults ARM_BUILD_TARGET to "local" (tune for the build
    # machine's arm core, baking in that core's extensions); pin its portable "common" mode instead
    # so default arm builds run on any armv8-a machine. ARM_BUILD_TARGET=local opts back in.
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
