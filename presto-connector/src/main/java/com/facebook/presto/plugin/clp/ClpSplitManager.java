package com.facebook.presto.plugin.clp;

import static java.util.Objects.requireNonNull;

import javax.inject.Inject;

import com.facebook.presto.spi.ConnectorSession;
import com.facebook.presto.spi.ConnectorSplitSource;
import com.facebook.presto.spi.ConnectorTableLayoutHandle;
import com.facebook.presto.spi.FixedSplitSource;
import com.facebook.presto.spi.connector.ConnectorSplitManager;
import com.facebook.presto.spi.connector.ConnectorTransactionHandle;

import com.facebook.presto.plugin.clp.split.ClpSplitProvider;

public class ClpSplitManager implements ConnectorSplitManager {
    private final ClpSplitProvider clpSplitProvider;

    @Inject
    public ClpSplitManager(ClpSplitProvider clpSplitProvider) {
        this.clpSplitProvider = requireNonNull(clpSplitProvider, "clpSplitProvider is null");
    }

    @Override
    public ConnectorSplitSource getSplits(
            ConnectorTransactionHandle transactionHandle,
            ConnectorSession session,
            ConnectorTableLayoutHandle layout,
            SplitSchedulingContext splitSchedulingContext
    ) {
        ClpTableLayoutHandle layoutHandle = (ClpTableLayoutHandle)layout;
        return new FixedSplitSource(clpSplitProvider.listSplits(layoutHandle));
    }
}
