package com.facebook.presto.plugin.clp;

import java.util.Set;

import com.facebook.presto.spi.Plugin;
import com.facebook.presto.spi.connector.ConnectorFactory;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableSet;

public class ClpPlugin implements Plugin {
    @Override
    public Iterable<ConnectorFactory> getConnectorFactories() {
        return ImmutableList.of(new ClpConnectorFactory());
    }

    @Override
    public Set<Class<?>> getFunctions() { return ImmutableSet.of(ClpFunctions.class); }
}
