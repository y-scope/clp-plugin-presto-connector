# Pin for the prestodb/presto upstream that velox-connector consumes via
# CMake FetchContent. Single source of truth — bump this one line to move
# to a newer presto commit. Both of these pick the pin up automatically:
#
#   * velox-connector/CMakeLists.txt              (plugin build)
#   * tools/build-packages/fetch-presto/          (host-side clone helper
#                                                  used at dep-image build
#                                                  time to derive the
#                                                  matching velox SHA)
set(PRESTO_NATIVE_EXECUTION_SHA "6e1942b72a9f32191dcd0ba49812f2ac96a25615")
