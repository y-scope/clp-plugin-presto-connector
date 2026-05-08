package com.facebook.presto.plugin.clp.optimization;

import java.util.Set;
import javax.inject.Inject;

import com.facebook.presto.spi.ConnectorPlanOptimizer;
import com.facebook.presto.spi.connector.ConnectorPlanOptimizerProvider;
import com.facebook.presto.spi.function.FunctionMetadataManager;
import com.facebook.presto.spi.function.StandardFunctionResolution;
import com.google.common.collect.ImmutableSet;

import com.facebook.presto.plugin.clp.split.filter.ClpSplitFilterProvider;

public class ClpPlanOptimizerProvider implements ConnectorPlanOptimizerProvider {
    private final FunctionMetadataManager functionManager;
    private final StandardFunctionResolution functionResolution;
    private final ClpSplitFilterProvider splitFilterProvider;

    @Inject
    public ClpPlanOptimizerProvider(
            FunctionMetadataManager functionManager,
            StandardFunctionResolution functionResolution,
            ClpSplitFilterProvider splitFilterProvider
    ) {
        this.functionManager = functionManager;
        this.functionResolution = functionResolution;
        this.splitFilterProvider = splitFilterProvider;
    }

    @Override
    public Set<ConnectorPlanOptimizer> getLogicalPlanOptimizers() {
        return ImmutableSet.of(new ClpUdfRewriter(functionManager));
    }

    @Override
    public Set<ConnectorPlanOptimizer> getPhysicalPlanOptimizers() {
        return ImmutableSet.of(
                new ClpComputePushDown(functionManager, functionResolution, splitFilterProvider)
        );
    }
}
