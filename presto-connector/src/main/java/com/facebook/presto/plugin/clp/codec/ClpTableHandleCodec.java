package com.facebook.presto.plugin.clp.codec;

import static com.facebook.presto.plugin.clp.codec.CodecUtils.readUtf8String;
import static com.facebook.presto.plugin.clp.codec.CodecUtils.writeUtf8String;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;

import com.facebook.presto.spi.ConnectorCodec;
import com.facebook.presto.spi.ConnectorTableHandle;
import com.facebook.presto.spi.SchemaTableName;

import com.facebook.presto.plugin.clp.ClpTableHandle;

public class ClpTableHandleCodec implements ConnectorCodec<ConnectorTableHandle> {
    // Wire format (C++ ClpConnectorProtocol::deserialize for ConnectorTableHandle):
    // schemaName : 2-byte BE length + UTF-8 bytes
    // tableName : 2-byte BE length + UTF-8 bytes
    // tablePath : 2-byte BE length + UTF-8 bytes

    @Override
    public byte[] serialize(ConnectorTableHandle handle) {
        try {
            if (!(handle instanceof ClpTableHandle)) {
                throw new IllegalArgumentException(
                        "Expected ClpTableHandle but got: " + (handle == null ? "null"
                                : handle.getClass().getName())
                );
            }
            ClpTableHandle tableHandle = (ClpTableHandle)handle;
            ByteArrayOutputStream byteOut = new ByteArrayOutputStream();
            DataOutputStream out = new DataOutputStream(byteOut);
            writeTableHandle(tableHandle, out);
            return byteOut.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to serialize ClpTableHandle", e);
        }
    }

    @Override
    public ConnectorTableHandle deserialize(byte[] bytes) {
        try {
            DataInputStream in = new DataInputStream(new ByteArrayInputStream(bytes));
            ClpTableHandle handle = readTableHandle(in);
            if (in.available() > 0) {
                throw new IOException(
                        "Unexpected trailing bytes in ClpTableHandle deserialization"
                );
            }
            return handle;
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to deserialize ClpTableHandle", e);
        }
    }

    static void writeTableHandle(ClpTableHandle handle, DataOutputStream out) throws IOException {
        writeUtf8String(handle.getSchemaTableName().getSchemaName(), out);
        writeUtf8String(handle.getSchemaTableName().getTableName(), out);
        writeUtf8String(handle.getTablePath(), out);
    }

    static ClpTableHandle readTableHandle(DataInputStream in) throws IOException {
        String schemaName = readUtf8String(in);
        String tableName = readUtf8String(in);
        String tablePath = readUtf8String(in);
        return new ClpTableHandle(new SchemaTableName(schemaName, tableName), tablePath);
    }
}
