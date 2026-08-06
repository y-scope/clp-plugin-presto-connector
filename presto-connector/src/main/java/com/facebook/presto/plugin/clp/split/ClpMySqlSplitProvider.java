/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.facebook.presto.plugin.clp.split;

import com.facebook.airlift.log.Logger;
import com.facebook.presto.plugin.clp.ClpConfig;
import com.facebook.presto.plugin.clp.split.metadata.ClpSplitMetadataConfig;
import com.facebook.presto.plugin.clp.split.metadata.ClpSplitMetadataExpressionConverter;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.SchemaTableName;
import com.facebook.presto.spi.function.FunctionMetadataManager;
import com.facebook.presto.spi.function.StandardFunctionResolution;
import com.facebook.presto.plugin.clp.ClpSplit;
import com.facebook.presto.plugin.clp.ClpTableHandle;
import com.facebook.presto.plugin.clp.ClpTableLayoutHandle;
import com.google.common.collect.ImmutableList;

import javax.inject.Inject;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.Set;

import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_MANDATORY_SPLIT_FILTER_NOT_VALID;
import static com.facebook.presto.plugin.clp.ClpSplit.SplitType.ARCHIVE;
import static java.lang.String.format;

public class ClpMySqlSplitProvider
        implements ClpSplitProvider
{
    // Column names
    public static final String ARCHIVES_TABLE_COLUMN_ID = "id";

    // Table suffixes
    public static final String ARCHIVES_TABLE_SUFFIX = "_archives";

    // SQL templates
    private static final String SQL_SELECT_ARCHIVES_TEMPLATE = format("SELECT `%s` FROM `%%s%%s%s` WHERE 1 = 1", ARCHIVES_TABLE_COLUMN_ID, ARCHIVES_TABLE_SUFFIX);

    private static final Logger log = Logger.get(ClpMySqlSplitProvider.class);

    private final ClpConfig config;
    private final ClpSplitMetadataConfig metadataConfig;
    private final FunctionMetadataManager functionManager;
    private final StandardFunctionResolution functionResolution;

    @Inject
    public ClpMySqlSplitProvider(
            ClpConfig config,
            ClpSplitMetadataConfig metadataConfig,
            FunctionMetadataManager functionManager,
            StandardFunctionResolution functionResolution)
    {
        try {
            Class.forName("com.mysql.cj.jdbc.Driver");
        }
        catch (ClassNotFoundException e) {
            log.error(e, "Failed to load MySQL JDBC driver");
            throw new RuntimeException("MySQL JDBC driver not found", e);
        }
        this.config = config;
        this.metadataConfig = metadataConfig;
        this.functionManager = functionManager;
        this.functionResolution = functionResolution;
    }

    @Override
    public List<ClpSplit> listSplits(ClpTableLayoutHandle clpTableLayoutHandle)
    {
        ImmutableList.Builder<ClpSplit> splits = new ImmutableList.Builder<>();
        ClpTableHandle clpTableHandle = clpTableLayoutHandle.getTable();
        String tablePath = clpTableHandle.getTablePath();
        String tableName = clpTableHandle.getSchemaTableName().getTableName();
        String archivePathQuery = format(SQL_SELECT_ARCHIVES_TEMPLATE, config.getMetadataTablePrefix(), tableName);

        // Rendered here rather than during planning, so that the SQL is built against this
        // store's own metadata columns.
        SchemaTableName schemaTableName = clpTableHandle.getSchemaTableName();
        if (false == clpTableLayoutHandle.getMetadataExpression().isPresent()) {
            // No predicate at all still has to satisfy the required columns, or the scan reads
            // every split.
            Set<String> required = metadataConfig.getRequiredColumns(schemaTableName);
            if (false == required.isEmpty()) {
                throw new PrestoException(CLP_MANDATORY_SPLIT_FILTER_NOT_VALID,
                        format("Query on %s must filter on %s", schemaTableName, required));
            }
        }
        else {
            ClpSplitMetadataExpressionConverter converter = new ClpSplitMetadataExpressionConverter(
                    functionResolution,
                    functionManager,
                    metadataConfig,
                    schemaTableName);
            archivePathQuery += " AND ("
                    + converter.toSqlCondition(clpTableLayoutHandle.getMetadataExpression().get()) + ")";
        }
        log.debug("Query for archive: %s", archivePathQuery);

        try (Connection connection = getConnection()) {
            // Fetch archive IDs and create splits
            try (PreparedStatement statement = connection.prepareStatement(archivePathQuery); ResultSet resultSet = statement.executeQuery()) {
                while (resultSet.next()) {
                    final String archiveId = resultSet.getString(ARCHIVES_TABLE_COLUMN_ID);
                    final String archivePath = tablePath + "/" + archiveId;
                    splits.add(new ClpSplit(archivePath, ARCHIVE, clpTableLayoutHandle.getKqlQuery()));
                }
            }
        }
        catch (SQLException e) {
            log.warn("Database error while processing splits for %s: %s", tableName, e);
        }

        ImmutableList<ClpSplit> filteredSplits = splits.build();
        log.debug("Number of splits: %s", filteredSplits.size());
        return filteredSplits;
    }

    private Connection getConnection()
            throws SQLException
    {
        Connection connection = DriverManager.getConnection(config.getMetadataDbUrl(), config.getMetadataDbUser(), config.getMetadataDbPassword());
        String dbName = config.getMetadataDbName();
        if (dbName != null && !dbName.isEmpty()) {
            connection.createStatement().execute(format("USE `%s`", dbName));
        }
        return connection;
    }
}
