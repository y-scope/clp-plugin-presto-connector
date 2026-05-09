package com.facebook.presto.plugin.clp.split.filter;

import static com.facebook.presto.plugin.clp.split.filter.ClpSplitFilterConfig.CustomSplitFilterOptions;

import java.io.IOException;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * Uses the given {@link CustomSplitFilterOptions} implementation to deserialize the
 * {@code "customOptions"} field in a {@link ClpSplitFilterConfig}. The implementation is determined
 * by the implemented {@link ClpSplitFilterProvider}.
 */
public class ClpSplitFilterConfigCustomOptionsDeserializer
        extends
        JsonDeserializer<CustomSplitFilterOptions> {
    private final Class<? extends CustomSplitFilterOptions> actualCustomSplitFilterOptionsClass;

    public ClpSplitFilterConfigCustomOptionsDeserializer(
            Class<? extends CustomSplitFilterOptions> actualCustomSplitFilterOptionsClass
    ) {
        this.actualCustomSplitFilterOptionsClass = actualCustomSplitFilterOptionsClass;
    }

    @Override
    public CustomSplitFilterOptions deserialize(JsonParser p, DeserializationContext ctxt)
            throws IOException {
        ObjectNode node = p.getCodec().readTree(p);
        ObjectMapper mapper = (ObjectMapper)p.getCodec();

        return mapper.treeToValue(node, actualCustomSplitFilterOptionsClass);
    }
}
