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

import com.facebook.presto.plugin.clp.metadata.ClpIntegrationTestMetadataProvider;
import com.facebook.presto.plugin.clp.split.ClpIntegrationTestSplitProvider;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.SchemaTableName;
import org.testng.annotations.AfterMethod;
import org.testng.annotations.BeforeMethod;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_INTEGRATION_TEST_FIXTURE_INVALID;
import static com.facebook.presto.plugin.clp.optimization.ClpUdfRewriter.JSON_STRING_PLACEHOLDER;
import static java.lang.String.format;
import static java.nio.charset.StandardCharsets.UTF_8;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.expectThrows;

/**
 * Covers the malformed fixtures the integration-test providers must reject rather than report as an
 * empty table, which would be indistinguishable from a table that genuinely has no rows.
 */
@Test(singleThreaded = true)
public class TestClpIntegrationTestFixtures
{
    private static final String TABLE_NAME = "test_table";

    private Path archiveDir;
    private Path tableDir;

    @BeforeMethod
    public void setUp() throws IOException
    {
        archiveDir = Files.createTempDirectory("clp-integration-test-fixtures");
        tableDir = Files.createDirectory(archiveDir.resolve(TABLE_NAME));
    }

    @AfterMethod
    public void tearDown() throws IOException
    {
        try (Stream<Path> paths = Files.walk(archiveDir)) {
            for (Path path : paths.sorted(Comparator.reverseOrder()).toArray(Path[]::new)) {
                Files.deleteIfExists(path);
            }
        }
    }

    @Test
    public void tableWithoutSchemaExposesJsonStringColumn()
    {
        List<ClpColumnHandle> columns = metadataProvider().listColumnHandles(schemaTableName());
        assertEquals(columns.size(), 1);
        assertEquals(columns.get(0).getColumnName(), JSON_STRING_PLACEHOLDER);
    }

    @Test
    public void schemaDirectoryIsRejected() throws IOException
    {
        Files.createDirectory(tableDir.resolve("schema.json"));
        assertFixtureInvalid(() -> metadataProvider().listColumnHandles(schemaTableName()));
    }

    @Test
    public void nullSchemaIsRejected() throws IOException
    {
        writeSchema("null");
        assertFixtureInvalid(() -> metadataProvider().listColumnHandles(schemaTableName()));
    }

    @Test
    public void nullSchemaEntryIsRejected() throws IOException
    {
        writeSchema("[null]");
        assertFixtureInvalid(() -> metadataProvider().listColumnHandles(schemaTableName()));
    }

    @Test
    public void schemaEntryWithoutTypeIsRejected() throws IOException
    {
        writeSchema("[{\"name\": \"a\"}]");
        assertFixtureInvalid(() -> metadataProvider().listColumnHandles(schemaTableName()));
    }

    // "." splits into no path at all, and a leading or doubled separator into an empty segment, so
    // ClpSchemaTree would otherwise throw ArrayIndexOutOfBoundsException or name a column "".
    @Test
    public void schemaEntryWithEmptyPathSegmentIsRejected() throws IOException
    {
        for (String name : new String[] {".", "", ".a", "a.", "a..b"}) {
            writeSchema(format("[{\"name\": \"%s\", \"type\": \"Integer\"}]", name));
            assertFixtureInvalid(() -> metadataProvider().listColumnHandles(schemaTableName()));
        }
    }

    @Test
    public void schemaDeclaresColumns() throws IOException
    {
        writeSchema("[{\"name\": \"a\", \"type\": \"Integer\"}]");
        List<ClpColumnHandle> columns = metadataProvider().listColumnHandles(schemaTableName());
        assertEquals(columns.size(), 1);
        assertEquals(columns.get(0).getColumnName(), "a");
    }

    @Test
    public void archiveNamedDirectoryIsRejected() throws IOException
    {
        Files.createDirectory(tableDir.resolve("invalid.clps"));
        assertFixtureInvalid(() -> new ClpIntegrationTestSplitProvider().listSplits(tableLayoutHandle()));
    }

    @Test
    public void archivesBecomeSplitsAndSchemaIsSkipped() throws IOException
    {
        writeSchema("[]");
        Files.write(tableDir.resolve("b.clps"), new byte[0]);
        Files.write(tableDir.resolve("a.clps"), new byte[0]);

        List<ClpSplit> splits = new ClpIntegrationTestSplitProvider().listSplits(tableLayoutHandle());
        assertEquals(splits.size(), 2);
        assertEquals(splits.get(0).getPath(), tableDir.resolve("a.clps").toString());
        assertEquals(splits.get(1).getPath(), tableDir.resolve("b.clps").toString());
    }

    @Test
    public void missingTableDirectoryIsRejected() throws IOException
    {
        Files.delete(tableDir);
        assertFixtureInvalid(() -> new ClpIntegrationTestSplitProvider().listSplits(tableLayoutHandle()));
    }

    private void writeSchema(String json) throws IOException
    {
        Files.write(tableDir.resolve("schema.json"), json.getBytes(UTF_8));
    }

    private ClpIntegrationTestMetadataProvider metadataProvider()
    {
        ClpConfig config = new ClpConfig().setIntegrationTestArchiveDir(archiveDir.toString());
        return new ClpIntegrationTestMetadataProvider(config);
    }

    private SchemaTableName schemaTableName()
    {
        return new SchemaTableName("default", TABLE_NAME);
    }

    private ClpTableLayoutHandle tableLayoutHandle()
    {
        return new ClpTableLayoutHandle(
                new ClpTableHandle(schemaTableName(), tableDir.toString()),
                Optional.empty(),
                Optional.empty());
    }

    private static void assertFixtureInvalid(Runnable runnable)
    {
        PrestoException e = expectThrows(PrestoException.class, runnable::run);
        assertEquals(e.getErrorCode(), CLP_INTEGRATION_TEST_FIXTURE_INVALID.toErrorCode());
    }
}
