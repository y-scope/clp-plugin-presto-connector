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

import com.facebook.presto.spi.ConnectorTableLayoutHandle;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.google.common.collect.ImmutableSortedMap;

import java.util.Map;
import java.util.Objects;
import java.util.Optional;

import static com.google.common.base.MoreObjects.toStringHelper;

public class ClpTableLayoutHandle
        implements ConnectorTableLayoutHandle
{
    private final ClpTableHandle table;
    private final Optional<String> kqlQuery;
    private final Optional<String> metadataSql;
    private final Map<String, String> queryConfig;

    @JsonCreator
    public ClpTableLayoutHandle(
            @JsonProperty("table") ClpTableHandle table,
            @JsonProperty("kqlQuery") Optional<String> kqlQuery,
            @JsonProperty("metadataFilterQuery") Optional<String> metadataSql,
            @JsonProperty("queryConfig") Map<String, String> queryConfig)
    {
        this.table = table;
        this.kqlQuery = kqlQuery;
        this.metadataSql = metadataSql;
        // Sorted for deterministic binary codec output
        this.queryConfig = queryConfig == null ? ImmutableSortedMap.of() : ImmutableSortedMap.copyOf(queryConfig);
    }

    public ClpTableLayoutHandle(ClpTableHandle table, Optional<String> kqlQuery, Optional<String> metadataSql)
    {
        this(table, kqlQuery, metadataSql, ImmutableSortedMap.of());
    }

    @JsonProperty
    public ClpTableHandle getTable()
    {
        return table;
    }

    @JsonProperty
    public Optional<String> getKqlQuery()
    {
        return kqlQuery;
    }

    @JsonProperty
    public Optional<String> getMetadataSql()
    {
        return metadataSql;
    }

    @JsonProperty
    public Map<String, String> getQueryConfig()
    {
        return queryConfig;
    }

    @Override
    public boolean equals(Object o)
    {
        if (this == o) {
            return true;
        }
        if (o == null || getClass() != o.getClass()) {
            return false;
        }
        ClpTableLayoutHandle that = (ClpTableLayoutHandle) o;
        return Objects.equals(table, that.table) &&
                Objects.equals(kqlQuery, that.kqlQuery) &&
                Objects.equals(metadataSql, that.metadataSql) &&
                Objects.equals(queryConfig, that.queryConfig);
    }

    @Override
    public int hashCode()
    {
        return Objects.hash(table, kqlQuery, metadataSql, queryConfig);
    }

    @Override
    public String toString()
    {
        return toStringHelper(this)
                .add("table", table)
                .add("kqlQuery", kqlQuery)
                .add("metadataSql", metadataSql)
                .add("queryConfig", queryConfig)
                .toString();
    }
}
