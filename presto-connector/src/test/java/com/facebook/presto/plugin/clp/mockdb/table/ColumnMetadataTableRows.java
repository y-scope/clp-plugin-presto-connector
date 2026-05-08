package com.facebook.presto.plugin.clp.mockdb.table;

import static com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider.COLUMN_METADATA_TABLE_COLUMN_NAME;
import static com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider.COLUMN_METADATA_TABLE_COLUMN_TYPE;
import static com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider.COLUMN_METADATA_TABLE_SUFFIX;
import static java.lang.String.format;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.fail;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.List;

import com.google.common.collect.ImmutableList;

import com.facebook.presto.plugin.clp.metadata.ClpSchemaTreeNodeType;

public class ColumnMetadataTableRows {
    private final List<String> names;
    private final List<ClpSchemaTreeNodeType> types;
    private final int numOfRows;

    public void insertToTable(Connection connection, String tablePrefix, String tableName) {
        String insertSql = format(
                "INSERT INTO `%s` (`%s`, `%s`) VALUES (?, ?)",
                format("%s%s%s", tablePrefix, tableName, COLUMN_METADATA_TABLE_SUFFIX),
                COLUMN_METADATA_TABLE_COLUMN_NAME,
                COLUMN_METADATA_TABLE_COLUMN_TYPE
        );
        try (PreparedStatement pstmt = connection.prepareStatement(insertSql)) {
            for (int i = 0; i < numOfRows; ++i) {
                pstmt.setString(1, names.get(i));
                pstmt.setByte(2, types.get(i).getType());
                pstmt.addBatch();
            }
            pstmt.executeBatch();
        } catch (SQLException e) {
            fail(e.getMessage());
        }
    }

    public ColumnMetadataTableRows(List<String> names, List<ClpSchemaTreeNodeType> types) {
        assertEquals(names.size(), types.size());
        this.names = ImmutableList.copyOf(names);
        this.types = ImmutableList.copyOf(types);
        numOfRows = names.size();
    }
}
