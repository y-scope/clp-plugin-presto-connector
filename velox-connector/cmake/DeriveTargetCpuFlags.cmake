# Defines `derive_target_cpu_flags(<output-variable> <helper-script>)`, which derives the
# target-CPU compiler flags the plugin must be built with and stores them in `<output-variable>`
# (set in the caller's scope). A Presto worker only loads a plugin built with the same target-CPU
# flags as itself, so the caller appends the result to `CMAKE_CXX_FLAGS`.
#
# Design: reuse upstream's flag derivation, don't reimplement it. The plugin's flags must track
# whatever Presto's own build produces, so this module invokes the same `get_cxx_flags` bash
# helper Presto's build uses — `<helper-script>` must point to it in the pinned Presto checkout;
# this module doesn't ship a copy — and the wrapper code below closely mirrors upstream's own
# invocation, kept that way deliberately so it stays easy to diff against upstream (including two
# inherited upstream bugs, marked TODO in the code). The only intended differences from upstream
# are two default values, marked `Deviation N` in the code and explained below.
#
# The `CPU_TARGET` environment variable selects the flags. It is a keyword naming the flag set
# the target worker was built with, not raw compiler flags — `get_cxx_flags` expands it:
#
#   +------------+---------------+-----------------------------------------------+
#   | CPU_TARGET | Architecture  | Flags                                         |
#   +------------+---------------+-----------------------------------------------+
#   | (blank)    | any           | Default: "avx" on x86_64 (Deviation 1);       |
#   |            |               | auto-detect elsewhere (Linux arm → "aarch64") |
#   | avx        | x86_64        | -mavx2 -mfma -mavx -mf16c -mlzcnt -mbmi2      |
#   | sse        | x86_64        | -msse4.2                                      |
#   | aarch64    | arm64 (Linux) | -march=armv8-a+crc+crypto (see below)         |
#   | arm64      | Apple Silicon | -mcpu=apple-m1+crc                            |
#   +------------+---------------+-----------------------------------------------+
#
# On arm, `ARM_BUILD_TARGET` (no effect elsewhere) additionally picks between upstream's two arm
# build styles: "common" — the portable armv8-a+crc+crypto baseline, the default (Deviation 2) —
# or "local", which tunes for the build machine's core: `get_cxx_flags` reads the CPU part number
# from the MIDR_EL1 register (via sysfs) and emits `-mcpu=neoverse-*` if it matches one of the
# Neoverse parts the helper knows (N1/N2/V1/V2, with an NVIDIA Grace special case); any other arm
# core — or a missing MIDR sysfs file — falls back to the "common" baseline. Use "local" only
# when the build machine matches the deployment hardware; core-specific extensions SIGILL on
# other cores.
#
# Both defaults match what the official presto-native docker images are built with ("avx" on
# x86_64; "common" on arm, whose images exist from 0.299 onward), so default builds load into
# official workers:
#
# 1. CPU_TARGET defaults to "avx" on x86_64 here in CMake, because upstream's identical default
#    lives in their Makefile (`CPU_TARGET ?= "avx"`), which this build never runs. Without it,
#    auto-detection on a non-AVX build machine would pick "sse", and official (avx) workers would
#    refuse to load the plugin — with no hint at build time.
# 2. ARM_BUILD_TARGET defaults to "common" instead of upstream's "local", so that default builds
#    are portable rather than tuned to the build machine.
#
# To find the value a given worker was built with: Folly's F14 hash table bakes the enabled CPU
# features into its ABI and enforces a match across the `dlopen` boundary via the
# `F14LinkCheck<(F14IntrinsicsMode)N>` symbol, so `nm -DC presto_server | grep F14LinkCheck`
# reads it off the worker binary — mode 2 means AVX2 (use "avx"); mode 1 means SSE/NEON only
# (use "sse" on x86_64, "aarch64" on arm64). The F14 link check is only the enforced part of the
# contract — matching the worker's full flag set is still the safe rule for the rest of the
# shared inline code.
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
