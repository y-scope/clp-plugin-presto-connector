package com.facebook.presto.plugin.clp;

import java.util.List;

import com.facebook.presto.spi.ColumnHandle;
import com.facebook.presto.spi.ConnectorSession;
import com.facebook.presto.spi.ConnectorSplit;
import com.facebook.presto.spi.RecordSet;
import com.facebook.presto.spi.connector.ConnectorRecordSetProvider;
import com.facebook.presto.spi.connector.ConnectorTransactionHandle;

public class ClpRecordSetProvider implements ConnectorRecordSetProvider {
    @Override
    public RecordSet getRecordSet(
            ConnectorTransactionHandle transactionHandle,
            ConnectorSession session,
            ConnectorSplit split,
            List<? extends ColumnHandle> columns
    ) {
        throw new UnsupportedOperationException("getRecordSet is not supported");
    }
}
