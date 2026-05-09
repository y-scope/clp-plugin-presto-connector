package com.facebook.presto.plugin.clp;

import static com.facebook.airlift.configuration.ConfigBinder.configBinder;
import static com.facebook.presto.plugin.clp.ClpConfig.MetadataProviderType;
import static com.facebook.presto.plugin.clp.ClpConfig.SplitFilterProviderType;
import static com.facebook.presto.plugin.clp.ClpConfig.SplitProviderType;
import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_UNSUPPORTED_METADATA_SOURCE;
import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_UNSUPPORTED_SPLIT_FILTER_SOURCE;
import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_UNSUPPORTED_SPLIT_SOURCE;

import com.facebook.airlift.configuration.AbstractConfigurationAwareModule;
import com.facebook.presto.spi.PrestoException;
import com.google.inject.Binder;
import com.google.inject.Scopes;

import com.facebook.presto.plugin.clp.metadata.ClpMetadataProvider;
import com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider;
import com.facebook.presto.plugin.clp.split.ClpMySqlSplitProvider;
import com.facebook.presto.plugin.clp.split.ClpSplitProvider;
import com.facebook.presto.plugin.clp.split.filter.ClpMySqlSplitFilterProvider;
import com.facebook.presto.plugin.clp.split.filter.ClpSplitFilterProvider;

public class ClpModule extends AbstractConfigurationAwareModule {
    @Override
    protected void setup(Binder binder) {
        binder.bind(ClpConnector.class).in(Scopes.SINGLETON);
        binder.bind(ClpMetadata.class).in(Scopes.SINGLETON);
        binder.bind(ClpRecordSetProvider.class).in(Scopes.SINGLETON);
        binder.bind(ClpSplitManager.class).in(Scopes.SINGLETON);
        configBinder(binder).bindConfig(ClpConfig.class);

        ClpConfig config = buildConfigObject(ClpConfig.class);

        if (SplitFilterProviderType.MYSQL == config.getSplitFilterProviderType()) {
            binder.bind(ClpSplitFilterProvider.class).to(ClpMySqlSplitFilterProvider.class).in(
                    Scopes.SINGLETON
            );
        } else {
            throw new PrestoException(
                    CLP_UNSUPPORTED_SPLIT_FILTER_SOURCE,
                    "Unsupported split filter provider type: " + config.getSplitFilterProviderType()
            );
        }

        if (config.getMetadataProviderType() == MetadataProviderType.MYSQL) {
            binder.bind(ClpMetadataProvider.class).to(ClpMySqlMetadataProvider.class).in(
                    Scopes.SINGLETON
            );
        } else {
            throw new PrestoException(
                    CLP_UNSUPPORTED_METADATA_SOURCE,
                    "Unsupported metadata provider type: " + config.getMetadataProviderType()
            );
        }

        if (config.getSplitProviderType() == SplitProviderType.MYSQL) {
            binder.bind(ClpSplitProvider.class).to(ClpMySqlSplitProvider.class).in(
                    Scopes.SINGLETON
            );
        } else {
            throw new PrestoException(
                    CLP_UNSUPPORTED_SPLIT_SOURCE,
                    "Unsupported split provider type: " + config.getSplitProviderType()
            );
        }
    }
}
