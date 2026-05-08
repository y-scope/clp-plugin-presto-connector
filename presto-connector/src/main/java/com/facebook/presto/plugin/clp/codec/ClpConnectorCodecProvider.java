package com.facebook.presto.plugin.clp.codec;

import static java.util.Objects.requireNonNull;

import java.util.Optional;

import com.facebook.presto.common.type.TypeManager;
import com.facebook.presto.spi.ColumnHandle;
import com.facebook.presto.spi.ConnectorCodec;
import com.facebook.presto.spi.ConnectorSplit;
import com.facebook.presto.spi.ConnectorTableHandle;
import com.facebook.presto.spi.ConnectorTableLayoutHandle;
import com.facebook.presto.spi.connector.ConnectorCodecProvider;
import com.facebook.presto.spi.connector.ConnectorTransactionHandle;

public class ClpConnectorCodecProvider implements ConnectorCodecProvider {
    private final TypeManager typeManager;

    public ClpConnectorCodecProvider(TypeManager typeManager) {
        this.typeManager = requireNonNull(typeManager, "typeManager is null");
    }

    @Override
    public Optional<ConnectorCodec<ConnectorTableHandle>> getConnectorTableHandleCodec() {
        return Optional.of(new ClpTableHandleCodec());
    }

    @Override
    public Optional<ConnectorCodec<ConnectorTableLayoutHandle>>
            getConnectorTableLayoutHandleCodec() {
        return Optional.of(new ClpTableLayoutHandleCodec());
    }

    @Override
    public Optional<ConnectorCodec<ColumnHandle>> getColumnHandleCodec() {
        return Optional.of(new ClpColumnHandleCodec(typeManager));
    }

    @Override
    public Optional<ConnectorCodec<ConnectorSplit>> getConnectorSplitCodec() {
        return Optional.of(new ClpSplitCodec());
    }

    @Override
    public Optional<ConnectorCodec<ConnectorTransactionHandle>>
            getConnectorTransactionHandleCodec() {
        return Optional.of(new ClpTransactionHandleCodec());
    }
}
