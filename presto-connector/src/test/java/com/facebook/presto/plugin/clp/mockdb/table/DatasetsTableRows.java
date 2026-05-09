package com.facebook.presto.plugin.clp.mockdb.table;

import static com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider.DATASETS_TABLE_COLUMN_ARCHIVE_STORAGE_DIRECTORY;
import static com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider.DATASETS_TABLE_COLUMN_NAME;
import static com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider.DATASETS_TABLE_SUFFIX;
import static java.lang.String.format;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.fail;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.List;

import com.google.common.collect.ImmutableList;

public class DatasetsTableRows {
    private final List<String> names;
    private final List<String> archivesStorageDirectories;
    private final int numOfRows;

    public void insertToTable(Connection connection, String tablePrefix) {
        final String insertSql = format(
                "INSERT INTO %s (%s, %s) VALUES (?, ?) "
                        + "ON DUPLICATE KEY UPDATE %s = VALUES(%s)",
                format("%s%s", tablePrefix, DATASETS_TABLE_SUFFIX),
                DATASETS_TABLE_COLUMN_NAME,
                DATASETS_TABLE_COLUMN_ARCHIVE_STORAGE_DIRECTORY,
                DATASETS_TABLE_COLUMN_ARCHIVE_STORAGE_DIRECTORY,
                DATASETS_TABLE_COLUMN_ARCHIVE_STORAGE_DIRECTORY
        );
        try (PreparedStatement pstmt = connection.prepareStatement(insertSql)) {
            for (int i = 0; i < numOfRows; ++i) {
                pstmt.setString(1, names.get(i));
                pstmt.setString(2, format("%s%s", archivesStorageDirectories.get(i), names.get(i)));
                pstmt.addBatch();
            }
            pstmt.executeBatch();
        } catch (SQLException e) {
            fail(e.getMessage());
        }
    }

    public DatasetsTableRows(List<String> names, List<String> archivesStorageDirectories) {
        assertEquals(names.size(), archivesStorageDirectories.size());
        this.names = ImmutableList.copyOf(names);
        this.archivesStorageDirectories = ImmutableList.copyOf(archivesStorageDirectories);
        this.numOfRows = names.size();
    }
}
