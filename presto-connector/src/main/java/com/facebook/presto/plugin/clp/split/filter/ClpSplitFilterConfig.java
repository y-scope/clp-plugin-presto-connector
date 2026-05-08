package com.facebook.presto.plugin.clp.split.filter;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Options for a how a column in a Presto query should be pushed down into a query against CLP's
 * metadata database (during split pruning):
 * <ul>
 * <li><b>{@code columnName}</b>: The column's name in the Presto query.</li>
 * <li><b>{@code customOptions}</b>: Options specific to the current
 * {@link ClpSplitFilterProvider}.</li>
 * <li><b>{@code required}</b> (optional, defaults to {@code false}): Whether the filter must be
 * present in the generated metadata query. If a required filter is missing or cannot be added to
 * the metadata query, the original query will be rejected.</li>
 * </ul>
 */
public class ClpSplitFilterConfig {
    @JsonProperty("columnName")
    public String columnName;

    @JsonProperty("customOptions")
    public CustomSplitFilterOptions customOptions;

    @JsonProperty("required")
    public boolean required;

    public interface CustomSplitFilterOptions {}
}
