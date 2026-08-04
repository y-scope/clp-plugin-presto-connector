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

import com.facebook.presto.spi.PrestoException;

import java.nio.file.Files;
import java.nio.file.Paths;

import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_INTEGRATION_TEST_FIXTURE_INVALID;
import static java.lang.String.format;

/**
 * Shared pieces of the integration-test metadata and split providers, which are selected
 * independently but read the same directory.
 */
public final class ClpIntegrationTestProviders
{
    public static final String INTEGRATION_TEST_PROVIDER_TYPE = "INTEGRATION_TEST";

    private ClpIntegrationTestProviders() {}

    // Checked at catalog load rather than on first use, so a misconfigured catalog is not reported
    // later as a table listing that is merely empty.
    public static void validateArchiveDir(ClpConfig config)
    {
        String archiveDir = config.getIntegrationTestArchiveDir();
        if (null == archiveDir || archiveDir.isEmpty()) {
            throw new PrestoException(CLP_INTEGRATION_TEST_FIXTURE_INVALID,
                    format("clp.integration-test-archive-dir must be set to use the %s providers",
                            INTEGRATION_TEST_PROVIDER_TYPE));
        }
        if (!Files.isDirectory(Paths.get(archiveDir))) {
            throw new PrestoException(CLP_INTEGRATION_TEST_FIXTURE_INVALID,
                    format("clp.integration-test-archive-dir is not a directory: %s", archiveDir));
        }
    }
}
