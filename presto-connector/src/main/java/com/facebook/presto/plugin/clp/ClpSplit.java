package com.facebook.presto.plugin.clp;

import static com.facebook.presto.spi.schedule.NodeSelectionStrategy.NO_PREFERENCE;
import static java.util.Objects.requireNonNull;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import com.facebook.presto.spi.ConnectorSplit;
import com.facebook.presto.spi.HostAddress;
import com.facebook.presto.spi.NodeProvider;
import com.facebook.presto.spi.schedule.NodeSelectionStrategy;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;

public class ClpSplit implements ConnectorSplit {
    private final String path;
    private final SplitType type;
    private final Optional<String> kqlQuery;

    @JsonCreator
    public ClpSplit(@JsonProperty("path")
    String path, @JsonProperty("type")
    SplitType type, @JsonProperty("kqlQuery")
    Optional<String> kqlQuery) {
        this.path = requireNonNull(path, "Split path is null");
        this.type = requireNonNull(type, "Split type is null");
        this.kqlQuery = kqlQuery;
    }

    @JsonProperty
    public String getPath() { return path; }

    @JsonProperty
    public SplitType getType() { return type; }

    @JsonProperty
    public Optional<String> getKqlQuery() { return kqlQuery; }

    @Override
    public NodeSelectionStrategy getNodeSelectionStrategy() { return NO_PREFERENCE; }

    @Override
    public List<HostAddress> getPreferredNodes(NodeProvider nodeProvider) {
        return ImmutableList.of();
    }

    @Override
    public Map<String, String> getInfo() {
        return ImmutableMap.of(
                "path",
                path,
                "type",
                type.toString(),
                "kqlQuery",
                kqlQuery.orElse("<null>")
        );
    }

    public enum SplitType {
        ARCHIVE, IR,
    }
}
