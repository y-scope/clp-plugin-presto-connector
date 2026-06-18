# Presto CLP Velox connector plugin

## Requirements

* CMake 3.28+
* GCC 11
* [Task] >= 3.49.1
* The official upstream Presto dev container:
  [`prestodb/presto-native-dependency`][presto-native-dependency]

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

[presto-native-dependency]: https://hub.docker.com/r/prestodb/presto-native-dependency
[Task]: https://taskfile.dev
