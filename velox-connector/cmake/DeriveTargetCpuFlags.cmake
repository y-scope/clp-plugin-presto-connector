# Defines `derive_target_cpu_flags(<output-variable> <helper-script>)`, which derives the
# target-CPU compiler flags the plugin must be built with and stores them in `<output-variable>`
# (set in the caller's scope). A Presto worker only loads a plugin built with the same target-CPU
# flags as itself, so the caller appends the result to `CMAKE_CXX_FLAGS`.
#
# Which flags come out:
# - By default, the flags the official presto-native docker images are built with: "avx" on
#   x86_64, and the portable armv8-a "common" baseline on arm (arm images exist from 0.299
#   onward).
# - To target a worker built with different flags, set the `CPU_TARGET`/`ARM_BUILD_TARGET`
#   environment variables — see "Target-CPU flags" in tools/build-packages/README.md.
#
# How it works: the keyword-to-flags mapping is `get_cxx_flags`, a bash function from Velox that
# `<helper-script>` must point to — this module doesn't ship a copy. The wrapper code below
# closely mirrors upstream's own invocation, kept that way deliberately so it stays easy to diff
# against upstream (including two inherited upstream bugs, marked TODO in the code). The only
# intended differences are the two defaults above, marked `Deviation N` in the code:
#
# 1. CPU_TARGET defaults to "avx" on x86_64 here in CMake, because upstream's identical default
#    lives in their Makefile (`CPU_TARGET ?= "avx"`), which this build never runs. Without it,
#    auto-detection on a non-AVX build machine would pick "sse", and official (avx) workers would
#    refuse to load the plugin — with no hint at build time.
# 2. ARM_BUILD_TARGET defaults to "common" instead of upstream's "local" (tune for the build
#    machine's arm core): "common" is what the official arm images use, and it runs on any
#    armv8-a machine.
#
# Upstream references, at the pinned Presto commit (refresh when bumping the pin in
# taskfile.yaml):
# - `get_cxx_flags`:
#   https://github.com/facebookincubator/velox/blob/0dbf1731fb6e03ae615a40cda8c9b33f7bfb3490/scripts/setup-helper-functions.sh#L91-L187
# - upstream's invocation of it:
#   https://github.com/prestodb/presto/blob/6e1942b72a9f32191dcd0ba49812f2ac96a25615/presto-native-execution/CMakeLists.txt#L20-L31
function(derive_target_cpu_flags OUTPUT_VARIABLE HELPER_SCRIPT)
    # Empty means "let get_cxx_flags auto-detect the build machine's CPU".
    set(CPU_TARGET "$ENV{CPU_TARGET}")

    # Deviation 1: default x86_64 to "avx" (see header).
    if(CPU_TARGET STREQUAL "" AND CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64")
        set(CPU_TARGET "avx")
    endif()

    # Deviation 2: default arm to the portable "common" baseline (see header).
    set(ARM_BUILD_TARGET "$ENV{ARM_BUILD_TARGET}")
    if(ARM_BUILD_TARGET STREQUAL "")
        set(ARM_BUILD_TARGET "common")
    endif()

    # TODO: This mirrors upstream's invocation, which lets `get_cxx_flags` report an unknown
    # keyword as text ("Architecture not supported!") with a zero exit status, so the text lands
    # in the flags and only surfaces later as confusing compile errors. Fix in Velox's
    # `scripts/setup-helper-functions.sh` (exit non-zero on the unknown-keyword case), then copy
    # the fix back here in a follow-up PR.
    execute_process(
        COMMAND bash -c
            "( export ARM_BUILD_TARGET=${ARM_BUILD_TARGET} && source ${HELPER_SCRIPT} && echo -n $(get_cxx_flags ${CPU_TARGET}))"
        OUTPUT_VARIABLE VELOX_TARGET_CPU_CXX_FLAGS
        RESULT_VARIABLE COMMAND_STATUS
    )

    # TODO: This mirrors upstream's check, but it can never fire: the `echo -n $(...)` wrapper
    # above discards the helper's exit status, so COMMAND_STATUS is always 0 — even on an
    # unsupported OS, where the helper exits 1. Fix in upstream's CMakeLists (both Velox's and
    # presto-native-execution's) by dropping the wrapper, then copy the fix back here in a
    # follow-up PR.
    if(COMMAND_STATUS EQUAL "1")
        message(FATAL_ERROR "Unable to determine compiler flags!")
    endif()

    message(STATUS "Target-CPU flags (get_cxx_flags): ${VELOX_TARGET_CPU_CXX_FLAGS}")
    set("${OUTPUT_VARIABLE}" "${VELOX_TARGET_CPU_CXX_FLAGS}" PARENT_SCOPE)
endfunction()
