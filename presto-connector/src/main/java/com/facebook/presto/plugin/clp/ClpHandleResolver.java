package com.facebook.presto.plugin.clp;

import com.facebook.presto.spi.ColumnHandle;
import com.facebook.presto.spi.ConnectorHandleResolver;
import com.facebook.presto.spi.ConnectorSplit;
import com.facebook.presto.spi.ConnectorTableHandle;
import com.facebook.presto.spi.ConnectorTableLayoutHandle;
import com.facebook.presto.spi.connector.ConnectorTransactionHandle;

public class ClpHandleResolver implements ConnectorHandleResolver {
    @Override
    public Class<? extends ConnectorTableHandle> getTableHandleClass() {
        return ClpTableHandle.class;
    }

    @Override
    public Class<? extends ConnectorTableLayoutHandle> getTableLayoutHandleClass() {
        return ClpTableLayoutHandle.class;
    }

    @Override
    public Class<? extends ColumnHandle> getColumnHandleClass() { return ClpColumnHandle.class; }

    @Override
    public Class<? extends ConnectorSplit> getSplitClass() { return ClpSplit.class; }

    @Override
    public Class<? extends ConnectorTransactionHandle> getTransactionHandleClass() {
        return ClpTransactionHandle.class;
    }
}
