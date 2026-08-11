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
package com.facebook.presto.plugin.clp;

import com.facebook.presto.plugin.clp.mockdb.ClpMockMetadataDatabase;
import com.facebook.presto.plugin.clp.mockdb.table.ArchivesTableRows;
import com.facebook.presto.plugin.clp.split.ClpMySqlSplitProvider;
import com.facebook.presto.plugin.clp.split.ClpSplitProvider;
import com.facebook.presto.spi.SchemaTableName;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import org.testng.annotations.AfterMethod;
import org.testng.annotations.BeforeMethod;
import org.testng.annotations.Test;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static com.facebook.presto.common.function.OperatorType.EQUAL;
import static com.facebook.presto.common.function.OperatorType.GREATER_THAN;
import static com.facebook.presto.common.function.OperatorType.GREATER_THAN_OR_EQUAL;
import static com.facebook.presto.common.function.OperatorType.LESS_THAN;
import static com.facebook.presto.common.function.OperatorType.LESS_THAN_OR_EQUAL;
import static com.facebook.presto.common.type.BigintType.BIGINT;
import static com.facebook.presto.common.type.BooleanType.BOOLEAN;
import static com.facebook.presto.sql.analyzer.TypeSignatureProvider.fromTypes;
import static com.facebook.presto.metadata.FunctionAndTypeManager.createTestFunctionAndTypeManager;
import static com.facebook.presto.plugin.clp.ClpMetadata.DEFAULT_SCHEMA_NAME;
import com.facebook.presto.common.function.OperatorType;
import com.facebook.presto.metadata.FunctionAndTypeManager;
import com.facebook.presto.spi.relation.CallExpression;
import com.facebook.presto.spi.relation.ConstantExpression;
import com.facebook.presto.spi.relation.RowExpression;
import com.facebook.presto.spi.relation.VariableReferenceExpression;
import com.facebook.presto.plugin.clp.split.metadata.ClpSplitMetadataConfig;
import com.facebook.presto.sql.relational.FunctionResolution;

import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.ARCHIVES_STORAGE_DIRECTORY_BASE;
import static com.google.common.collect.ImmutableList.toImmutableList;
import static java.lang.String.format;
import static org.testng.Assert.assertEquals;

@Test(singleThreaded = true)
public class TestClpSplit
{
    private ClpMockMetadataDatabase mockMetadataDatabase;
    private FunctionAndTypeManager functionAndTypeManager;
    private ClpSplitProvider clpSplitProvider;
    private Map<String, ArchivesTableRows> tableSplits;

    @BeforeMethod
    public void setUp()
    {
        mockMetadataDatabase = ClpMockMetadataDatabase
                .builder()
                .build();
        ImmutableList.Builder<String> tableNamesBuilder = ImmutableList.builder();
        ImmutableMap.Builder<String, ArchivesTableRows> splitsMapBuilder = ImmutableMap.builder();

        int numTables = 3;
        int numSplitsPerTable = 10;

        for (int i = 0; i < numTables; i++) {
            String tableName = "test_split_" + i;
            tableNamesBuilder.add(tableName);

            ImmutableList.Builder<String> idsBuilder = ImmutableList.builder();
            ImmutableList.Builder<Long> beginTimestampsBuilder = ImmutableList.builder();
            ImmutableList.Builder<Long> endTimestampsBuilder = ImmutableList.builder();
            for (int j = 0; j < numSplitsPerTable; j++) {
                // We generate synthetic begin_timestamp and end_timestamp values for each split
                // by offsetting two base timestamps (1700000000000L and 1705000000000L) with a
                // fixed increment per split (10^10 * j).
                idsBuilder.add(format("id_%s", j));
                beginTimestampsBuilder.add(1700000000000L + 10000000000L * j);
                endTimestampsBuilder.add(1705000000000L + 10000000000L * j);
            }
            splitsMapBuilder.put(tableName, new ArchivesTableRows(idsBuilder.build(), beginTimestampsBuilder.build(), endTimestampsBuilder.build()));
        }

        mockMetadataDatabase.addTableToDatasetsTableIfNotExist(tableNamesBuilder.build());
        tableSplits = splitsMapBuilder.build();
        mockMetadataDatabase.addSplits(tableSplits);
        ClpConfig config = new ClpConfig()
                .setPolymorphicTypeEnabled(true)
                .setMetadataDbUrl(mockMetadataDatabase.getUrl())
                .setMetadataDbUser(mockMetadataDatabase.getUsername())
                .setMetadataDbPassword(mockMetadataDatabase.getPassword())
                .setMetadataTablePrefix(mockMetadataDatabase.getTablePrefix());
        functionAndTypeManager = createTestFunctionAndTypeManager();
        clpSplitProvider = new ClpMySqlSplitProvider(
                config,
                new ClpSplitMetadataConfig(
                        config.setSplitMetadataConfigPath(writeSplitMetadataConfig()),
                        functionAndTypeManager),
                functionAndTypeManager,
                new FunctionResolution(functionAndTypeManager.getFunctionAndTypeResolver()));
    }

    @AfterMethod
    public void tearDown()
    {
        if (null != mockMetadataDatabase) {
            mockMetadataDatabase.teardown();
        }
    }

    @Test
    public void testListSplits()
    {
        for (Map.Entry<String, ArchivesTableRows> entry : tableSplits.entrySet()) {
            // Archive j covers [1700000000000 + 10^10*j, 1705000000000 + 10^10*j], so the ten are
            // disjoint with gaps between them. A predicate on `timestamp` prunes to whichever
            // archives could hold a matching row.
            compareListSplitsResult(entry, Optional.empty(), ImmutableList.of(0, 1, 2, 3, 4, 5, 6, 7, 8, 9));

            // A lower bound keeps every archive whose end reaches it.
            compareListSplitsResult(entry, comparison(GREATER_THAN, 1745000000001L),
                    ImmutableList.of(5, 6, 7, 8, 9));
            compareListSplitsResult(entry, comparison(GREATER_THAN, 1795000000001L), ImmutableList.of());
            compareListSplitsResult(entry, comparison(GREATER_THAN_OR_EQUAL, 1700000000000L),
                    ImmutableList.of(0, 1, 2, 3, 4, 5, 6, 7, 8, 9));

            // An upper bound keeps every archive whose beginning falls below it.
            compareListSplitsResult(entry, comparison(LESS_THAN, 1699999999999L), ImmutableList.of());
            compareListSplitsResult(entry, comparison(LESS_THAN_OR_EQUAL, 1710000000000L),
                    ImmutableList.of(0, 1));

            // Equality needs the archive's range to straddle the value.
            compareListSplitsResult(entry, comparison(EQUAL, 1700000000000L), ImmutableList.of(0));
            compareListSplitsResult(entry, comparison(EQUAL, 1795000000000L), ImmutableList.of(9));
            compareListSplitsResult(entry, comparison(EQUAL, 1715000000000L), ImmutableList.of(1));
            // Falls in the gap between archives 1 and 2, so no archive can hold it.
            compareListSplitsResult(entry, comparison(EQUAL, 1715000000001L), ImmutableList.of());
        }
    }

    /**
     * @param operator
     * @param value
     * @return A predicate {@code timestamp <operator> value}, which the split provider rewrites
     * against the archive table's begin/end columns.
     */
    private Optional<RowExpression> comparison(OperatorType operator, long value)
    {
        return Optional.of(new CallExpression(
                operator.name(),
                functionAndTypeManager.resolveOperator(operator, fromTypes(BIGINT, BIGINT)),
                BOOLEAN,
                ImmutableList.of(
                        new VariableReferenceExpression(Optional.empty(), "timestamp", BIGINT),
                        new ConstantExpression(value, BIGINT))));
    }

    /**
     * Declares the archive table's begin/end columns as the bounds of a logical `timestamp`
     * column, which is what lets a predicate on `timestamp` prune archives.
     *
     * @return The path of the written config.
     */
    private static String writeSplitMetadataConfig()
    {
        try {
            Path file = Files.createTempFile("split-metadata", ".json");
            file.toFile().deleteOnExit();
            Files.write(file, ("{\"\": {\"metaColumns\": {"
                    + "\"begin_timestamp\": {\"type\": \"bigint\", \"asRangeBoundOf\": \"timestamp\","
                    + " \"boundType\": \"LOWER\"},"
                    + "\"end_timestamp\": {\"type\": \"bigint\", \"asRangeBoundOf\": \"timestamp\","
                    + " \"boundType\": \"UPPER\"}}}}").getBytes(StandardCharsets.UTF_8));
            return file.toString();
        }
        catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private void compareListSplitsResult(
            Map.Entry<String, ArchivesTableRows> entry,
            Optional<RowExpression> metadataExpression,
            List<Integer> expectedSplitIndexes)
    {
        String tableName = entry.getKey();
        String tablePath = ARCHIVES_STORAGE_DIRECTORY_BASE + tableName;
        ClpTableLayoutHandle layoutHandle = new ClpTableLayoutHandle(
                new ClpTableHandle(new SchemaTableName(DEFAULT_SCHEMA_NAME, tableName), tablePath),
                Optional.empty(),
                metadataExpression);
        List<String> expectedSplitPaths = expectedSplitIndexes.stream()
                .map(expectedSplitIndex -> format("%s/%s", tablePath, entry.getValue().getIds().get(expectedSplitIndex)))
                .collect(toImmutableList());
        List<ClpSplit> actualSplits = clpSplitProvider.listSplits(layoutHandle);
        assertEquals(actualSplits.size(), expectedSplitPaths.size());

        ImmutableList<String> actualSplitPaths = actualSplits.stream()
                .map(ClpSplit::getPath)
                .collect(toImmutableList());

        assertEquals(actualSplitPaths, expectedSplitPaths);
    }
}
