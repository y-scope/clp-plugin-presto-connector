# Integration tests

Integration tests for the CLP Presto connector, run against a real two-node cluster: a Java
coordinator and a native (C++) worker, both loading the connector plugin.

## Why a real cluster

The worker plugin leaves Velox symbols undefined for the worker process to resolve at load time, so
a test binary has nothing to link against. Running queries through a real worker exercises it
without building Velox into the toolchain image.

## Running

```shell
task integration-tests:run
```

That builds the init-container image the cluster installs the plugins from, then brings the cluster
up and tears it down. `--use-running-cluster` reuses one already up; `--keep-cluster` leaves it
running afterwards. Markers select subsets (`archive`, `ir`, `pushdown`, `schema`, `udf`), e.g.
`task integration-tests:run -- -m ir`.

### By hand

`task package` builds the installer image the compose file defaults to. Then, from this directory:

```shell
docker compose up
```

The worker waits for the coordinator to report healthy, so a clean `up` ends with both nodes
running and the worker counted in `activeWorkers`. Query it with any Presto client:

```shell
presto-cli --server localhost:18080 --catalog clp --schema default --execute "SHOW TABLES"
```

Tear it down with `docker compose down -v`. The `-v` matters: the plugin directories are volumes,
so without it the next `up` reuses the previously installed plugin rather than the one you just
built.

Four variables override the defaults:

| Variable | Default | What it changes |
| --- | --- | --- |
| `PRESTO_VERSION` | `0.299` | Tag of both server images |
| `CLP_PLUGIN_INSTALLER_IMAGE` | `ghcr.io/y-scope/clp-plugin-presto-connector:0.1.0-SNAPSHOT` | Installer image `task package` produces |
| `CLP_INTEGRATION_TEST_FIXTURE_DIR` | `./fixtures` | Fixture tree the cluster mounts |
| `CLP_INTEGRATION_TEST_COORDINATOR_PORT` | `18080` | Host port the coordinator is published on |

Only the coordinator's port is published, and it defaults to 18080 rather than 8080 to stay clear
of whatever else is running. The ports inside the containers are fixed and cannot collide with the
host. If 18080 is taken, `docker compose up` fails with a bind error; set the variable and retry.

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
