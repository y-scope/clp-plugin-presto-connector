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
package com.facebook.presto.plugin.clp.metadata;

import com.facebook.presto.plugin.clp.ClpColumnHandle;
import com.facebook.presto.plugin.clp.ClpConfig;
import com.facebook.presto.plugin.clp.ClpTableHandle;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.SchemaTableName;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.common.collect.ImmutableList;
import com.google.inject.Inject;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static com.facebook.presto.common.type.VarcharType.VARCHAR;
import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_INTEGRATION_TEST_FIXTURE_INVALID;
import static com.facebook.presto.plugin.clp.optimization.ClpUdfRewriter.JSON_STRING_PLACEHOLDER;
import static java.lang.String.format;
import static java.util.Objects.requireNonNull;

/**
 * Discovers table schemas from a directory of CLP archives rather than a metadata database. Each
 * directory under {@code clp.integration-test-archive-dir} is a table, declaring its columns in an
 * optional {@code schema.json}.
 */
public class ClpIntegrationTestMetadataProvider
        implements ClpMetadataProvider
{
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final String SCHEMA_FILE_NAME = "schema.json";

    private final ClpConfig config;
    private final Path archiveDir;

    @Inject
    public ClpIntegrationTestMetadataProvider(ClpConfig config)
    {
        this.config = requireNonNull(config, "config is null");
        // Presence and directory-ness are checked by the factory's validateConfig at startup.
        this.archiveDir = Paths.get(config.getIntegrationTestArchiveDir());
    }

    @Override
    public List<ClpColumnHandle> listColumnHandles(SchemaTableName schemaTableName)
    {
        Path schemaFile = archiveDir.resolve(schemaTableName.getTableName()).resolve(SCHEMA_FILE_NAME);
        if (!Files.isRegularFile(schemaFile)) {
            return ImmutableList.of(new ClpColumnHandle(JSON_STRING_PLACEHOLDER, VARCHAR));
        }

        // A list of {"name", "type"} entries, not a map: CLP stores a field under every type it was
        // written with, so one name can appear more than once.
        List<Map<String, String>> columns;
        try {
            columns = OBJECT_MAPPER.readValue(
                    schemaFile.toFile(), new TypeReference<List<Map<String, String>>>() {});
        }
        catch (IOException e) {
            throw new PrestoException(CLP_INTEGRATION_TEST_FIXTURE_INVALID,
                    format("Failed to read %s", schemaFile), e);
        }

        ClpSchemaTree schemaTree = new ClpSchemaTree(config.isPolymorphicTypeEnabled());
        for (Map<String, String> column : columns) {
            String name = column.get("name");
            String type = column.get("type");
            if (null == name || null == type) {
                throw new PrestoException(CLP_INTEGRATION_TEST_FIXTURE_INVALID,
                        format("Entry in %s needs both \"name\" and \"type\": %s", schemaFile, column));
            }
            try {
                schemaTree.addColumn(name, ClpSchemaTreeNodeType.valueOf(type).getType());
            }
            catch (IllegalArgumentException e) {
                throw new PrestoException(CLP_INTEGRATION_TEST_FIXTURE_INVALID,
                        format("Unknown column type \"%s\" in %s; expected a ClpSchemaTreeNodeType name", type, schemaFile), e);
            }
        }
        return schemaTree.collectColumnHandles();
    }

    @Override
    public List<ClpTableHandle> listTableHandles(String schema)
    {
        if (!Files.isDirectory(archiveDir)) {
            throw new PrestoException(CLP_INTEGRATION_TEST_FIXTURE_INVALID,
                    format("clp.integration-test-archive-dir is not a directory: %s", archiveDir));
        }

        ImmutableList.Builder<ClpTableHandle> tables = ImmutableList.builder();
        try (Stream<Path> entries = Files.list(archiveDir)) {
            entries.filter(Files::isDirectory)
                    .sorted()
                    .forEach(entry -> tables.add(new ClpTableHandle(
                            new SchemaTableName(schema, entry.getFileName().toString()),
                            entry.toString())));
        }
        catch (IOException e) {
            throw new PrestoException(CLP_INTEGRATION_TEST_FIXTURE_INVALID,
                    format("Failed to list %s", archiveDir), e);
        }
        return tables.build();
    }
}
