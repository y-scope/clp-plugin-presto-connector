/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.facebook.presto.plugin.clp.metadata;

import com.facebook.presto.plugin.clp.ClpConfig;

/**
 * Registers a {@link ClpMetadataProvider} implementation under a name selectable via the
 * {@code clp.metadata-provider-type} catalog property.
 * <p></p>
 * Implementations are discovered with {@link java.util.ServiceLoader}, so a provider ships as an
 * ordinary jar on the plugin's classpath declaring this interface in
 * {@code META-INF/services/com.facebook.presto.plugin.clp.metadata.ClpMetadataProviderFactory}. No
 * change to the connector's own sources is required to add one.
 * <p></p>
 * Metadata providers (schema discovery) and split providers (archive discovery) are selected
 * independently, so a catalog may pair any metadata provider with any split provider.
 */
public interface ClpMetadataProviderFactory
{
    /**
     * Returns the name that selects this provider via {@code clp.metadata-provider-type}.
     * <p></p>
     * Matching is case-insensitive. Names must be unique across all registered factories; a
     * collision is a configuration error and fails connector startup.
     *
     * @return the provider's selector name; must be non-null and non-empty
     */
    String getName();

    /**
     * Returns the implementation Guice binds to {@link ClpMetadataProvider}.
     *
     * @return the provider implementation class
     */
    Class<? extends ClpMetadataProvider> getProviderClass();

    /**
     * Validates the catalog properties this provider requires, before Guice instantiates it.
     * <p></p>
     * Implement this to fail fast with an actionable message rather than surfacing a missing
     * setting as a null dereference at query time. Called only for the selected provider.
     *
     * @param config the connector's resolved configuration
     * @throws com.facebook.presto.spi.PrestoException if a required property is missing or invalid
     */
    default void validateConfig(ClpConfig config)
    {
    }
}
