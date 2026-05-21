# Presto Connector

## Requirements

* JDK 17
* [Maven] 3.8+
* [Task] 3.38.0+

## Building

```shell
task build
```

Or with Maven directly:

```shell
mvn package -DskipTests
```

## Testing

```shell
task test
```

## Linting

Before submitting a pull request, ensure you've run the linting commands below and either fixed any violations or suppressed the warnings.


### Running the linters

 To check for formatting and linting issues:
 
```shell
task lint:check
```

To auto-fix formatting and check for remaining linting issues:

```shell
task lint:fix
```

[Maven]: https://maven.apache.org/
[Task]: https://taskfile.dev

---
