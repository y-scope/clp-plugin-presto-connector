package com.facebook.presto.plugin.clp;

import static com.google.common.base.MoreObjects.toStringHelper;

import java.util.Objects;
import java.util.Optional;

import com.facebook.presto.spi.ConnectorTableLayoutHandle;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;

public class ClpTableLayoutHandle implements ConnectorTableLayoutHandle {
    private final ClpTableHandle table;
    private final Optional<String> kqlQuery;
    private final Optional<String> metadataSql;

    @JsonCreator
    public ClpTableLayoutHandle(@JsonProperty("table")
    ClpTableHandle table, @JsonProperty("kqlQuery")
    Optional<String> kqlQuery, @JsonProperty("metadataFilterQuery")
    Optional<String> metadataSql) {
        this.table = table;
        this.kqlQuery = kqlQuery;
        this.metadataSql = metadataSql;
    }

    @JsonProperty
    public ClpTableHandle getTable() { return table; }

    @JsonProperty
    public Optional<String> getKqlQuery() { return kqlQuery; }

    @JsonProperty
    public Optional<String> getMetadataSql() { return metadataSql; }

    @Override
    public boolean equals(Object o) {
        if (this == o) { return true; }
        if (o == null || getClass() != o.getClass()) { return false; }
        ClpTableLayoutHandle that = (ClpTableLayoutHandle)o;
        return Objects.equals(table, that.table) && Objects.equals(kqlQuery, that.kqlQuery)
                && Objects.equals(metadataSql, that.metadataSql);
    }

    @Override
    public int hashCode() {
        return Objects.hash(table, kqlQuery, metadataSql);
    }

    @Override
    public String toString() {
        return toStringHelper(this).add("table", table).add("kqlQuery", kqlQuery).add(
                "metadataSql",
                metadataSql
        ).toString();
    }
}
