package com.facebook.presto.plugin.clp.metadata;

import java.util.List;

import com.facebook.presto.spi.SchemaTableName;

import com.facebook.presto.plugin.clp.ClpColumnHandle;
import com.facebook.presto.plugin.clp.ClpTableHandle;

/**
 * A provider for metadata that describes what tables exist in the CLP connector, and what columns
 * exist in each of those tables.
 */
public interface ClpMetadataProvider {
    /**
     * @param schemaTableName the name of the schema and the table
     * @return the list of column handles for the given table.
     */
    List<ClpColumnHandle> listColumnHandles(SchemaTableName schemaTableName);

    /**
     * @param schema the name of the schema
     * @return the list of table handles in the specified schema
     */
    List<ClpTableHandle> listTableHandles(String schema);
}
