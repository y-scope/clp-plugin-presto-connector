package com.facebook.presto.plugin.clp.codec;

import com.facebook.presto.spi.ConnectorCodec;
import com.facebook.presto.spi.connector.ConnectorTransactionHandle;

import com.facebook.presto.plugin.clp.ClpTransactionHandle;

public class ClpTransactionHandleCodec implements ConnectorCodec<ConnectorTransactionHandle> {
    // Wire format (C++ ClpConnectorProtocol::deserialize for ConnectorTransactionHandle):
    // (0 bytes — empty payload)

    @Override
    public byte[] serialize(ConnectorTransactionHandle handle) {
        if (handle != ClpTransactionHandle.INSTANCE) {
            throw new IllegalArgumentException(
                    "Expected ClpTransactionHandle but got: " + handle.getClass().getName()
            );
        }
        return new byte[0];
    }

    @Override
    public ConnectorTransactionHandle deserialize(byte[] bytes) {
        if (bytes.length > 0) {
            throw new IllegalArgumentException(
                    "Expected empty payload for ClpTransactionHandle but got " + bytes.length
                            + " bytes"
            );
        }
        return ClpTransactionHandle.INSTANCE;
    }
}
