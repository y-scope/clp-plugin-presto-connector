# Presto Connector

Java plugin for the Presto coordinator. 

![Coordinator Architecture](../assets/clp-presto-coordinator.webp)

This plugin implements the connector interfaces (red boxes in the diagram above) that allow Presto to query against the schemaless CLP format efficiently:

- Table and column resolution (Metadata API): These interfaces are necessary so that Presto can determine what tables (CLP datasets) exist, and what columns should be directly exposed in each table.

- Query plan optimization (Optimizer API): These interfaces are necessary so that the connector can rewrite the logical query plan to push down any operations that CLP can handle when searching the data in each archive.

- Splits retrieval (Data Splits API): These interfaces are necessary so that the connector can query CLP’s metadata database to retrieve and return the splits (CLP archives) relevant to a particular query.

## Requirements

* JDK 17
* [Maven] 3.8+

## Building


```shell
mvn package -DskipTests
```

## Testing

```shell
mvn test
```


```

[Maven]: https://maven.apache.org/

---
