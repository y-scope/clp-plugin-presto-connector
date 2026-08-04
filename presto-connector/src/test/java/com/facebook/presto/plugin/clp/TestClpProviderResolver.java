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
package com.facebook.presto.plugin.clp;

import com.facebook.presto.plugin.clp.metadata.ClpMetadataProviderFactory;
import com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProvider;
import com.facebook.presto.plugin.clp.metadata.ClpMySqlMetadataProviderFactory;
import com.facebook.presto.plugin.clp.split.ClpMySqlSplitProvider;
import com.facebook.presto.plugin.clp.split.ClpMySqlSplitProviderFactory;
import com.facebook.presto.plugin.clp.split.ClpSplitProviderFactory;
import com.facebook.presto.spi.PrestoException;
import org.testng.annotations.Test;

import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_UNSUPPORTED_METADATA_SOURCE;
import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_UNSUPPORTED_SPLIT_SOURCE;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertTrue;
import static org.testng.Assert.fail;

/**
 * Covers ServiceLoader-based provider resolution: that the built-in factories are actually
 * discoverable through {@code META-INF/services}, and that an unresolvable name fails with a
 * message naming what is registered.
 */
public class TestClpProviderResolver
{
    @Test
    public void testResolvesBuiltInSplitProvider()
    {
        ClpSplitProviderFactory factory = ClpProviderResolver.resolve(
                ClpSplitProviderFactory.class,
                ClpSplitProviderFactory::getName,
                "MYSQL",
                "clp.split-provider-type",
                CLP_UNSUPPORTED_SPLIT_SOURCE);
        assertEquals(factory.getClass(), ClpMySqlSplitProviderFactory.class);
        assertEquals(factory.getProviderClass(), ClpMySqlSplitProvider.class);
    }

    @Test
    public void testResolvesBuiltInMetadataProvider()
    {
        ClpMetadataProviderFactory factory = ClpProviderResolver.resolve(
                ClpMetadataProviderFactory.class,
                ClpMetadataProviderFactory::getName,
                "MYSQL",
                "clp.metadata-provider-type",
                CLP_UNSUPPORTED_METADATA_SOURCE);
        assertEquals(factory.getClass(), ClpMySqlMetadataProviderFactory.class);
        assertEquals(factory.getProviderClass(), ClpMySqlMetadataProvider.class);
    }

    /**
     * The default in {@link ClpConfig} must resolve, or a catalog that omits the property fails to
     * start.
     */
    @Test
    public void testDefaultProviderTypeResolves()
    {
        ClpConfig config = new ClpConfig();
        assertEquals(config.getSplitProviderType(), ClpConfig.DEFAULT_PROVIDER_TYPE);
        assertEquals(config.getMetadataProviderType(), ClpConfig.DEFAULT_PROVIDER_TYPE);

        ClpProviderResolver.resolve(
                ClpSplitProviderFactory.class,
                ClpSplitProviderFactory::getName,
                config.getSplitProviderType(),
                "clp.split-provider-type",
                CLP_UNSUPPORTED_SPLIT_SOURCE);
        ClpProviderResolver.resolve(
                ClpMetadataProviderFactory.class,
                ClpMetadataProviderFactory::getName,
                config.getMetadataProviderType(),
                "clp.metadata-provider-type",
                CLP_UNSUPPORTED_METADATA_SOURCE);
    }

    @Test
    public void testNameMatchingIsCaseInsensitive()
    {
        for (String name : new String[] {"mysql", "MySql", "  MYSQL  "}) {
            ClpSplitProviderFactory factory = ClpProviderResolver.resolve(
                    ClpSplitProviderFactory.class,
                    ClpSplitProviderFactory::getName,
                    name,
                    "clp.split-provider-type",
                    CLP_UNSUPPORTED_SPLIT_SOURCE);
            assertEquals(factory.getProviderClass(), ClpMySqlSplitProvider.class);
        }
    }

    @Test
    public void testUnknownNameListsRegisteredProviders()
    {
        try {
            ClpProviderResolver.resolve(
                    ClpSplitProviderFactory.class,
                    ClpSplitProviderFactory::getName,
                    "NOT_A_PROVIDER",
                    "clp.split-provider-type",
                    CLP_UNSUPPORTED_SPLIT_SOURCE);
            fail("expected a PrestoException for an unregistered provider name");
        }
        catch (PrestoException e) {
            assertEquals(e.getErrorCode(), CLP_UNSUPPORTED_SPLIT_SOURCE.toErrorCode());
            assertTrue(
                    e.getMessage().contains("NOT_A_PROVIDER"),
                    "message should name the unresolvable value: " + e.getMessage());
            assertTrue(
                    e.getMessage().contains("MYSQL"),
                    "message should list what is registered: " + e.getMessage());
        }
    }

    @Test
    public void testBlankNameIsRejected()
    {
        for (String name : new String[] {null, "", "   "}) {
            try {
                ClpProviderResolver.resolve(
                        ClpSplitProviderFactory.class,
                        ClpSplitProviderFactory::getName,
                        name,
                        "clp.split-provider-type",
                        CLP_UNSUPPORTED_SPLIT_SOURCE);
                fail("expected a PrestoException for a blank provider name");
            }
            catch (PrestoException e) {
                assertEquals(e.getErrorCode(), CLP_UNSUPPORTED_SPLIT_SOURCE.toErrorCode());
            }
        }
    }
}
