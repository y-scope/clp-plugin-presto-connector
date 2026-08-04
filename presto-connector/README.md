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

Both default to `MYSQL`, backed by CLP's own metadata database. They are resolved separately, so a
catalog may pair any metadata provider with any split provider.

### Adding a provider

Providers are discovered with `ServiceLoader`, so a new one needs no change to this repository.

1. Implement `ClpSplitProvider` (or `ClpMetadataProvider`). Declare dependencies with `@Inject`;
   Guice constructs the provider, so implementations are free to require different dependencies.
2. Implement the matching factory, `ClpSplitProviderFactory` or `ClpMetadataProviderFactory`,
   returning a unique `getName()` and the provider's class. Override `validateConfig` to fail
   startup with an actionable message when a required catalog property is missing.
3. Declare the factory in your jar's `META-INF/services/<factory FQCN>`, either
   `com.facebook.presto.plugin.clp.split.ClpSplitProviderFactory` or
   `com.facebook.presto.plugin.clp.metadata.ClpMetadataProviderFactory`.
4. Drop the jar into the same Presto plugin directory as this connector and set the provider type
   to your factory's name. Name matching is case-insensitive.

Presto loads every jar in a plugin directory with one class loader, so a provider jar sees the
connector's interfaces without being shaded into its artifact. Two factories claiming the same name
is a startup error, and an unrecognized provider type fails with the list of registered names.

[Task]: https://taskfile.dev
