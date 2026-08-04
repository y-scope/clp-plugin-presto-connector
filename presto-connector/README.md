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

These cover the coordinator in isolation: SQL-to-KQL conversion, plan rewriting, codec round-trips,
and metadata and split listing against a mock database. For both sides running together, see
[integration-tests/README.md](../integration-tests/README.md).

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

## Pruning splits

A split provider that queries a metadata store can skip archives that cannot hold a matching row.
`clp.split-metadata-config-path` names a JSON file describing what that store knows about each
archive, so a predicate can be turned into a query against it:

```json
{
  "": {
    "metaColumns": {
      "begin_timestamp": {
        "type": "bigint",
        "asRangeBoundOf": "timestamp",
        "boundType": "LOWER"
      },
      "end_timestamp": {
        "type": "bigint",
        "asRangeBoundOf": "timestamp",
        "boundType": "UPPER"
      }
    },
    "requiredColumns": [
      {"column": "timestamp", "reason": "a query without it reads every archive"}
    ]
  },
  "logs.events": {
    "metaColumns": {
      "host": {"type": "varchar", "exposedAs": "hostname"}
    }
  }
}
```

Each key is a scope: `""` applies to every table, a schema name to that schema, and
`<schema>.<table>` to one table. Broader scopes apply to narrower ones, and a narrower scope
overrides a column the broader one declared.

Within `metaColumns`, each entry is named as the store knows it, and:

| Field | Meaning |
|---|---|
| `type` | The column's Presto type. |
| `exposedAs` | The name a query uses, when it differs from the store's. |
| `asRangeBoundOf` | The data column this one bounds, when the store records a range per archive. |
| `boundType` | `LOWER` or `UPPER`, which end of that range this column holds. |

A pair of columns bounding the same data column is what makes pruning possible: a predicate on
`timestamp` becomes a comparison against `begin_timestamp` and `end_timestamp`, keeping only the
archives whose range overlaps the values the predicate admits. Declaring one end is allowed, and
prunes predicates that constrain that end only.

`requiredColumns` names columns a query must filter on. A query that omits one fails rather than
reading every archive, and `reason` is reported when it does.

Without the property, no metadata columns exist and nothing is pruned, which is what a provider
that lists archives from a directory needs.

[Task]: https://taskfile.dev
