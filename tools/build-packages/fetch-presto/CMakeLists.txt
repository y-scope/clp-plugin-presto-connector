cmake_minimum_required(VERSION 3.28.3)
project(fetch-presto LANGUAGES NONE)

include(FetchContent)

# The pin lives next to its primary consumer (velox-connector); fetch-presto
# is just a host-side clone helper that materializes the same source tree on
# disk so tools/build-packages/dependency-image/lib.sh can read the velox
# submodule pointer out of it. Same SHA, both consumers, one line to bump.
include("${CMAKE_CURRENT_LIST_DIR}/../../../velox-connector/cmake/PrestoPin.cmake")

FetchContent_Declare(
    presto_native_execution
    GIT_REPOSITORY    "https://github.com/prestodb/presto.git"
    GIT_TAG           "${PRESTO_NATIVE_EXECUTION_SHA}"
    GIT_SUBMODULES    "presto-native-execution/velox"
    GIT_SUBMODULES_RECURSE OFF
)
FetchContent_MakeAvailable(presto_native_execution)
