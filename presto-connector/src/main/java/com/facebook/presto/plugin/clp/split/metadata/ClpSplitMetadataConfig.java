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
import com.facebook.presto.common.type.TypeManager;
import com.facebook.presto.common.type.TypeSignature;
import com.facebook.presto.plugin.clp.ClpConfig;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.SchemaTableName;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import com.google.common.collect.ImmutableSet;
import com.google.inject.Inject;

import java.io.IOException;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_SPLIT_METADATA_CONFIG_NOT_FOUND;
import static java.util.Objects.requireNonNull;

/**
 * Describes the metadata columns that a split provider can prune on, loaded from the JSON file
 * named by {@code clp.split-metadata-config-path}.
 * <p>
 * Entries are keyed by scope, from broadest to narrowest: {@code ""} for every table, a schema
 * name, or {@code "<schema>.<table>"}. Narrower scopes override broader ones per column.
 * <p>
 * Without the property, every accessor reports nothing, which is what a provider backed by a
 * directory listing rather than a queryable store needs.
 */
public class ClpSplitMetadataConfig
{
    private final Map<String, ScopeConfig> scopes;
    private final TypeManager typeManager;

    /**
     * One metadata column. A column either stands on its own or, when {@code asRangeBoundOf} is
     * set, forms one end of the range covering a data column: a split whose
     * {@code [lower, upper]} straddles a predicate's value may hold matching rows.
     */
    public static class MetaColumn
    {
        @JsonProperty("type")
        public String type;

        @JsonProperty("exposedAs")
        public String exposedAs;

        @JsonProperty("asRangeBoundOf")
        public String asRangeBoundOf;

        @JsonProperty("boundType")
        public BoundType boundType;
    }

    public enum BoundType
    {
        LOWER,
        UPPER
    }

    /** A metadata column that a query must filter on, so a scan cannot read every split. */
    public static class RequiredColumn
    {
        @JsonProperty("column")
        public String column;

        @JsonProperty("reason")
        public String reason;
    }

    public static class ScopeConfig
    {
        @JsonProperty("metaColumns")
        public Map<String, MetaColumn> metaColumns = ImmutableMap.of();

        @JsonProperty("requiredColumns")
        public List<RequiredColumn> requiredColumns = ImmutableList.of();
    }

    /** The metadata columns bounding one data column. Either end may be absent. */
    public static class RangeBounds
    {
        private final String lower;
        private final String upper;

        RangeBounds(String lower, String upper)
        {
            this.lower = lower;
            this.upper = upper;
        }

        public Optional<String> getLower()
        {
            return Optional.ofNullable(lower);
        }

        public Optional<String> getUpper()
        {
            return Optional.ofNullable(upper);
        }
    }

    @Inject
    public ClpSplitMetadataConfig(ClpConfig config, TypeManager typeManager)
    {
        requireNonNull(config, "config is null");
        this.typeManager = requireNonNull(typeManager, "typeManager is null");

        String path = config.getSplitMetadataConfigPath();
        if (null == path) {
            this.scopes = ImmutableMap.of();
            return;
        }

        try {
            this.scopes = ImmutableMap.copyOf(new ObjectMapper().readValue(
                    Paths.get(path).toFile(),
                    new TypeReference<Map<String, ScopeConfig>>() {}));
        }
        catch (IOException e) {
            throw new PrestoException(CLP_SPLIT_METADATA_CONFIG_NOT_FOUND,
                    "Failed to read clp.split-metadata-config-path: " + path, e);
        }
    }

    /**
     * @param table
     * @return The metadata columns visible to a query against {@code table}, by the name a query
     * uses, in declaration order.
     */
    public Map<String, Type> getMetadataColumns(SchemaTableName table)
    {
        ImmutableMap.Builder<String, Type> columns = ImmutableMap.builder();
        for (Map.Entry<String, MetaColumn> entry : mergedColumns(table).entrySet()) {
            columns.put(
                    exposedName(entry.getKey(), entry.getValue()),
                    typeManager.getType(TypeSignature.parseTypeSignature(entry.getValue().type)));
        }
        return columns.build();
    }

    /**
     * @param table
     * @return The columns a query against {@code table} must filter on.
     */
    public Set<String> getRequiredColumns(SchemaTableName table)
    {
        ImmutableSet.Builder<String> required = ImmutableSet.builder();
        for (ScopeConfig scope : scopesFor(table)) {
            for (RequiredColumn column : scope.requiredColumns) {
                required.add(column.column);
            }
        }
        return required.build();
    }

    /**
     * @param table
     * @param column A data column a predicate names.
     * @return The metadata columns bounding {@code column}, or empty when it has none and a
     * predicate on it cannot prune splits.
     */
    public Optional<RangeBounds> getRangeBounds(SchemaTableName table, String column)
    {
        String lower = null;
        String upper = null;
        for (Map.Entry<String, MetaColumn> entry : mergedColumns(table).entrySet()) {
            MetaColumn meta = entry.getValue();
            if (false == column.equals(meta.asRangeBoundOf) || null == meta.boundType) {
                continue;
            }
            if (BoundType.LOWER == meta.boundType) {
                lower = entry.getKey();
            }
            else {
                upper = entry.getKey();
            }
        }
        return (null == lower && null == upper)
                ? Optional.empty()
                : Optional.of(new RangeBounds(lower, upper));
    }

    private static String exposedName(String declaredName, MetaColumn column)
    {
        return (null == column.exposedAs) ? declaredName : column.exposedAs;
    }

    /** Merges the scopes covering {@code table}, letting a narrower scope override a broader one. */
    private Map<String, MetaColumn> mergedColumns(SchemaTableName table)
    {
        Map<String, MetaColumn> merged = new LinkedHashMap<>();
        for (ScopeConfig scope : scopesFor(table)) {
            merged.putAll(scope.metaColumns);
        }
        return merged;
    }

    private List<ScopeConfig> scopesFor(SchemaTableName table)
    {
        ImmutableList.Builder<ScopeConfig> applicable = ImmutableList.builder();
        for (String key : ImmutableList.of(
                "",
                table.getSchemaName(),
                table.getSchemaName() + "." + table.getTableName())) {
            ScopeConfig scope = scopes.get(key);
            if (null != scope) {
                applicable.add(scope);
            }
        }
        return applicable.build();
    }
}
