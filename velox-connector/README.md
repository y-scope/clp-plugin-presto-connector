# Presto CLP Velox connector plugin

## Requirements

* An environment with Velox's [dependencies][velox-deps-setup] installed
  * For example, Presto's dev container:
    [prestodb/presto-native-dependency][presto-native-dependency]
    * NOTE: Due a bug in GCC 12 that's used in the container, log-surgeon won't compile. Instead,
        you'll need to explicitly set the following environment variables to point at GCC 11:

        ```shell
        export CC="gcc"
        export CXX="g++"
        ```

* [Task] >= 3.49.1

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
