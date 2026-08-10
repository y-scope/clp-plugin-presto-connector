# Presto CLP coordinator connector plugin

## Requirements

* JDK 17
* [Task] >= 3.49.1

## Building

```shell
task presto-connector:build
```

## Testing

```shell
task presto-connector:test
```

## Providers

The connector always reads CLP archives the same way; what varies is where it learns *what exists
and where*. Two independent extension points cover that:

| Extension point | Answers | Selected by |
|---|---|---|
| `ClpMetadataProvider` | which tables and columns exist | `clp.metadata-provider-type` |
| `ClpSplitProvider` | which archives a query must read | `clp.split-provider-type` |

Both default to `MYSQL`, backed by CLP's own metadata database, and are selected separately, so a
catalog may pair any metadata provider with any split provider. `INTEGRATION_TEST` serves both from
a directory of archives named by `clp.integration-test-archive-dir`, which is how the connector is
exercised without a metadata database.

[Task]: https://taskfile.dev
