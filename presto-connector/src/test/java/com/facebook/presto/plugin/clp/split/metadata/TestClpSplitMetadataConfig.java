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
package com.facebook.presto.plugin.clp.split.metadata;

import com.facebook.presto.common.type.Type;
import com.facebook.presto.plugin.clp.ClpConfig;
import com.facebook.presto.spi.SchemaTableName;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableSet;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static com.facebook.presto.common.type.BigintType.BIGINT;
import static com.facebook.presto.common.type.VarcharType.VARCHAR;
import static com.facebook.presto.metadata.FunctionAndTypeManager.createTestFunctionAndTypeManager;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertFalse;
import static org.testng.Assert.assertTrue;

public class TestClpSplitMetadataConfig
{
    private static final SchemaTableName EVENTS = new SchemaTableName("logs", "events");

    private static ClpSplitMetadataConfig load(String json)
            throws IOException
    {
        Path file = Files.createTempFile("split-metadata", ".json");
        file.toFile().deleteOnExit();
        Files.write(file, json.getBytes(StandardCharsets.UTF_8));
        ClpConfig config = new ClpConfig().setSplitMetadataConfigPath(file.toString());
        return new ClpSplitMetadataConfig(config, createTestFunctionAndTypeManager());
    }

    /**
     * A provider whose splits come from a directory listing sets no config, and must then see no
     * metadata columns rather than fail.
     */
    @Test
    public void testAbsentConfigReportsNothing()
    {
        ClpSplitMetadataConfig config =
                new ClpSplitMetadataConfig(new ClpConfig(), createTestFunctionAndTypeManager());

        assertTrue(config.getMetadataColumns(EVENTS).isEmpty());
        assertTrue(config.getRequiredColumns(EVENTS).isEmpty());
        assertFalse(config.getRangeBounds(EVENTS, "timestamp").isPresent());
    }

    @Test
    public void testExposedNameDefaultsToDeclaredName()
            throws IOException
    {
        ClpSplitMetadataConfig config = load(
                "{\"\": {\"metaColumns\": {"
                        + "\"begin_timestamp\": {\"type\": \"bigint\"},"
                        + "\"host\": {\"type\": \"varchar\", \"exposedAs\": \"hostname\"}}}}");

        Map<String, Type> columns = config.getMetadataColumns(EVENTS);
        assertEquals(columns.get("begin_timestamp"), BIGINT);
        assertEquals(columns.get("hostname"), VARCHAR);
        assertFalse(columns.containsKey("host"));
    }

    /**
     * Two metadata columns bound one data column, which is what lets a predicate on that column
     * prune splits.
     */
    @Test
    public void testRangeBoundsPairTwoColumns()
            throws IOException
    {
        ClpSplitMetadataConfig config = load(
                "{\"\": {\"metaColumns\": {"
                        + "\"begin_ts\": {\"type\": \"bigint\", \"asRangeBoundOf\": \"timestamp\","
                        + " \"boundType\": \"LOWER\"},"
                        + "\"end_ts\": {\"type\": \"bigint\", \"asRangeBoundOf\": \"timestamp\","
                        + " \"boundType\": \"UPPER\"}}}}");

        ClpSplitMetadataConfig.RangeBounds bounds = config.getRangeBounds(EVENTS, "timestamp").get();
        assertEquals(bounds.getLower(), Optional.of("begin_ts"));
        assertEquals(bounds.getUpper(), Optional.of("end_ts"));
        assertFalse(config.getRangeBounds(EVENTS, "unbounded").isPresent());
    }

    /** Only one end may be declared, leaving predicates on the other end unprunable. */
    @Test
    public void testRangeBoundsMayBeOneSided()
            throws IOException
    {
        ClpSplitMetadataConfig config = load(
                "{\"\": {\"metaColumns\": {\"begin_ts\": {\"type\": \"bigint\","
                        + " \"asRangeBoundOf\": \"timestamp\", \"boundType\": \"LOWER\"}}}}");

        ClpSplitMetadataConfig.RangeBounds bounds = config.getRangeBounds(EVENTS, "timestamp").get();
        assertEquals(bounds.getLower(), Optional.of("begin_ts"));
        assertFalse(bounds.getUpper().isPresent());
    }

    /** A column declared without a bound type is not a range bound, even naming a data column. */
    @Test
    public void testBoundTypeIsRequiredForARangeBound()
            throws IOException
    {
        ClpSplitMetadataConfig config = load(
                "{\"\": {\"metaColumns\": {\"begin_ts\": {\"type\": \"bigint\","
                        + " \"asRangeBoundOf\": \"timestamp\"}}}}");

        assertFalse(config.getRangeBounds(EVENTS, "timestamp").isPresent());
    }

    @Test
    public void testNarrowerScopeOverridesBroader()
            throws IOException
    {
        ClpSplitMetadataConfig config = load(
                "{\"\": {\"metaColumns\": {\"ts\": {\"type\": \"bigint\"}}},"
                        + "\"logs\": {\"metaColumns\": {\"host\": {\"type\": \"varchar\"}}},"
                        + "\"logs.events\": {\"metaColumns\": {\"ts\": {\"type\": \"varchar\"}}}}");

        Map<String, Type> columns = config.getMetadataColumns(EVENTS);
        assertEquals(columns.get("ts"), VARCHAR, "table scope should override the global type");
        assertEquals(columns.get("host"), VARCHAR);

        // A table in the same schema keeps the global definition.
        assertEquals(
                config.getMetadataColumns(new SchemaTableName("logs", "other")).get("ts"),
                BIGINT);
    }

    @Test
    public void testScopesDoNotLeakAcrossSchemas()
            throws IOException
    {
        ClpSplitMetadataConfig config = load(
                "{\"logs\": {\"metaColumns\": {\"host\": {\"type\": \"varchar\"}}}}");

        assertTrue(config.getMetadataColumns(new SchemaTableName("metrics", "events")).isEmpty());
    }

    @Test
    public void testRequiredColumnsAccumulateAcrossScopes()
            throws IOException
    {
        ClpSplitMetadataConfig config = load(
                "{\"\": {\"requiredColumns\": [{\"column\": \"timestamp\","
                        + " \"reason\": \"scans every split otherwise\"}]},"
                        + "\"logs.events\": {\"requiredColumns\": [{\"column\": \"host\"}]}}");

        assertEquals(config.getRequiredColumns(EVENTS), ImmutableSet.copyOf(
                ImmutableList.of("timestamp", "host")));
    }
}
