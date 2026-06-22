# Presto CLP Velox connector plugin

## Requirements

* CMake 3.28+
* GCC 11 (`g++-11`); newer GCC versions can fail to build some of the dependencies
* [Task] >= 3.49.1
* System libraries: `libssl-dev`, `libevent-dev`, `libcurl4-openssl-dev`

## Building

```shell
task velox-connector:build
```

Or with CMake directly:

```shell
task velox-connector:deps:install-all
cmake -S velox-connector -B build/velox-connector
cmake --build build/velox-connector -j
```

The built plugin will be at `build/velox-connector/libclp-plugin-velox-connector.so`.

[Task]: https://taskfile.dev
