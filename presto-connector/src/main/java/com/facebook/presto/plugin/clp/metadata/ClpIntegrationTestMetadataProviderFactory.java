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

import static com.facebook.presto.plugin.clp.ClpIntegrationTestProviders.INTEGRATION_TEST_PROVIDER_TYPE;
import static com.facebook.presto.plugin.clp.ClpIntegrationTestProviders.validateArchiveDir;

/**
 * Registers {@link ClpIntegrationTestMetadataProvider}, which discovers table schemas from a
 * directory of CLP archives rather than a metadata database.
 */
public class ClpIntegrationTestMetadataProviderFactory
        implements ClpMetadataProviderFactory
{
    @Override
    public String getName()
    {
        return INTEGRATION_TEST_PROVIDER_TYPE;
    }

    @Override
    public Class<? extends ClpMetadataProvider> getProviderClass()
    {
        return ClpIntegrationTestMetadataProvider.class;
    }

    @Override
    public void validateConfig(ClpConfig config)
    {
        validateArchiveDir(config);
    }
}
