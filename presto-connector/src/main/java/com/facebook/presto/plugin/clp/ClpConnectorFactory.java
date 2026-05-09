package com.facebook.presto.plugin.clp;

import static java.util.Objects.requireNonNull;

import java.util.Map;

import com.facebook.airlift.bootstrap.Bootstrap;
import com.facebook.airlift.json.JsonModule;
import com.facebook.presto.common.type.TypeManager;
import com.facebook.presto.spi.ConnectorHandleResolver;
import com.facebook.presto.spi.NodeManager;
import com.facebook.presto.spi.connector.Connector;
import com.facebook.presto.spi.connector.ConnectorContext;
import com.facebook.presto.spi.connector.ConnectorFactory;
import com.facebook.presto.spi.function.FunctionMetadataManager;
import com.facebook.presto.spi.function.StandardFunctionResolution;
import com.google.inject.Injector;

public class ClpConnectorFactory implements ConnectorFactory {
    public static final String CONNECTOR_NAME = "clp";

    @Override
    public String getName() { return CONNECTOR_NAME; }

    @Override
    public ConnectorHandleResolver getHandleResolver() { return new ClpHandleResolver(); }

    @Override
    public Connector create(
            String catalogName,
            Map<String, String> config,
            ConnectorContext context
    ) {
        requireNonNull(catalogName, "catalogName is null");
        requireNonNull(config, "config is null");
        try {
            Bootstrap app = new Bootstrap(new JsonModule(), new ClpModule(), binder -> {
                binder.bind(FunctionMetadataManager.class).toInstance(
                        context.getFunctionMetadataManager()
                );
                binder.bind(NodeManager.class).toInstance(context.getNodeManager());
                binder.bind(StandardFunctionResolution.class).toInstance(
                        context.getStandardFunctionResolution()
                );
                binder.bind(TypeManager.class).toInstance(context.getTypeManager());
            });

            Injector injector = app.doNotInitializeLogging().setRequiredConfigurationProperties(
                    config
            ).initialize();

            return injector.getInstance(ClpConnector.class);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
