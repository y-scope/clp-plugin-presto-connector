# Integration tests

Integration tests for the CLP Presto connector, run against a real two-node cluster: a Java
coordinator and a native (C++) worker, both loading the connector plugin.

## Why a real cluster

The worker plugin leaves Velox symbols undefined for the worker process to resolve at load time, so
a test binary has nothing to link against. Running queries through a real worker exercises it
without building Velox into the toolchain image.

## Running

```shell
task package    # builds the init-container image the cluster installs the plugins from
task integration-tests:run
```

The session brings the cluster up and tears it down. `--use-running-cluster` reuses one already
up; `--keep-cluster` leaves it running afterwards. Markers select subsets (`archive`, `ir`,
`pushdown`, `schema`, `udf`), e.g. `task integration-tests:run -- -m ir`.

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

## The cluster

`docker-compose.yaml` brings up a Java coordinator and a native worker from the stock
`ghcr.io/y-scope/presto` and `ghcr.io/y-scope/presto-native` images. The plugins are installed by
the same init-container image a real deployment uses, built by `task package`: an install service
per node writes into a volume that node then mounts as its plugin directory. Nothing copies build
output by hand, so the harness exercises the shipped installer rather than a re-implementation of
it.

Each node's configuration lives under `etc/`, mounted over the image's wholesale, so every file the
server needs must be present here -- including a `jvm.config` for the coordinator, which refuses to
start without one. Ours carries the single flag the server demands and none of the image's heap or
GC tuning.

The connector is pointed at the fixture tree by the catalog properties in `etc/coordinator/catalog/`
and `etc/worker/catalog/`:

```properties
clp.metadata-provider-type=INTEGRATION_TEST
clp.split-provider-type=INTEGRATION_TEST
clp.split-filter-provider-type=INTEGRATION_TEST
clp.integration-test-archive-dir=/fixtures
```

The archive directory is mounted at the **same path** in both services: the coordinator enumerates
it to build splits, and the worker opens the paths those splits carry.

Two cluster settings are load-bearing and easy to get wrong:

* The worker's `presto.version` must match the coordinator's exactly. A mismatched worker registers
  and answers health checks, but is never counted in `activeWorkers`, so queries queue forever.
* `use-connector-provided-serialization-codecs=true` on the coordinator. The connector ships its
  own split and handle codecs; without this the worker cannot deserialize the splits it is sent.

## Known failures

Two tests are marked `xfail` and do not block.

The `timestamps` table stores one instant four ways: an ISO string, a float, and two integers
(microseconds and nanoseconds). All four read back as the same instant, but a filter on that column
matches only two of them -- the integer-encoded records are dropped.

```sql
SELECT timestamp_timestamp FROM timestamps;
-- 2025-04-30 08:50:05.000, four times

SELECT COUNT(*) FROM timestamps WHERE timestamp_timestamp = TIMESTAMP '2025-04-30 08:50:05';
-- 2
```

The two tests assert 4, so they fail today. `test_projected_and_filtered_disagree` asserts today's
numbers instead, so the suite fails if the behaviour ever changes. Fixing it needs a decision about
whether this connector or CLP should change.
