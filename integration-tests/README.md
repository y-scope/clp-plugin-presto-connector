# Integration tests

End-to-end tests for the CLP Presto connector, run against a real two-node cluster: a Java
coordinator and a native (C++) worker, both loading the connector plugin.

## Fixtures

`fixtures/` is mounted into the cluster as-is; nothing generates it. A table is a **directory** of
archives, mirroring how CLP stores a dataset and how `ClpMySqlSplitProvider` addresses it
(`<tablePath>/<archiveId>`), so a directory holding several archives fans out to several splits.

Each directory also holds the `.ndjson` records its archives were compressed from. Nothing reads
them -- the connector only picks up `.clps` and `.clp.zst` -- but they are how you derive an
expected value without decompressing anything.

To add a table, add a directory. To add a split to one, drop in another archive.

A table may carry a `schema.json` listing `{"name", "type"}` entries, one per (field, storage type)
pair, mirroring the rows the MySQL provider reads from `column_metadata`. Such a table exposes real
typed columns. A table without one exposes the single `__json_string` column, read through the
`CLP_GET_*` UDFs. Both access paths are covered.

The list form matters: CLP stores a field under every type it was written with, and `ClpSchemaTree`
splits those into suffixed columns (`timestamp_bigint`, `timestamp_double`). A map keyed by field
name could only declare one, silently misrepresenting any polymorphic field.
