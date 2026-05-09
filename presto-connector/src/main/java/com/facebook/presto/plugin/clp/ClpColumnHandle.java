package com.facebook.presto.plugin.clp;

import static com.google.common.base.MoreObjects.toStringHelper;

import java.util.Objects;

import com.facebook.presto.common.type.Type;
import com.facebook.presto.spi.ColumnHandle;
import com.facebook.presto.spi.ColumnMetadata;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;

public class ClpColumnHandle implements ColumnHandle {
    private final String columnName;
    private final String originalColumnName;
    private final Type columnType;

    @JsonCreator
    public ClpColumnHandle(@JsonProperty("columnName")
    String columnName, @JsonProperty("originalColumnName")
    String originalColumnName, @JsonProperty("columnType")
    Type columnType) {
        this.columnName = columnName;
        this.originalColumnName = originalColumnName;
        this.columnType = columnType;
    }

    public ClpColumnHandle(String columnName, Type columnType) {
        this(columnName, columnName, columnType);
    }

    @JsonProperty
    public String getColumnName() { return columnName; }

    @JsonProperty
    public String getOriginalColumnName() { return originalColumnName; }

    @JsonProperty
    public Type getColumnType() { return columnType; }

    public ColumnMetadata getColumnMetadata() {
        return ColumnMetadata.builder().setName(columnName).setType(columnType).build();
    }

    @Override
    public int hashCode() {
        return Objects.hash(columnName, originalColumnName, columnType);
    }

    @Override
    public boolean equals(Object obj) {
        if (this == obj) { return true; }
        if (obj == null || getClass() != obj.getClass()) { return false; }
        ClpColumnHandle other = (ClpColumnHandle)obj;
        return Objects.equals(this.columnName, other.columnName) && Objects.equals(
                this.originalColumnName,
                other.originalColumnName
        ) && Objects.equals(this.columnType, other.columnType);
    }

    @Override
    public String toString() {
        return toStringHelper(this).add("columnName", columnName).add(
                "originalColumnName",
                originalColumnName
        ).add("columnType", columnType).toString();
    }
}
