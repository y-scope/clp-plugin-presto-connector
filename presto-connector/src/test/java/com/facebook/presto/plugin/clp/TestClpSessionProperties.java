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

import com.facebook.presto.spi.session.PropertyMetadata;
import org.testng.annotations.Test;

import static com.facebook.presto.plugin.clp.ClpSessionProperties.CASE_INSENSITIVE;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertFalse;
import static org.testng.Assert.assertTrue;

public class TestClpSessionProperties
{
    @Test
    public void testCaseInsensitiveDefaultsToFalse()
    {
        PropertyMetadata<?> property = getCaseInsensitiveProperty(new ClpConfig());
        assertFalse((Boolean) property.getDefaultValue());
    }

    @Test
    public void testCaseInsensitiveDefaultsToConfigValue()
    {
        PropertyMetadata<?> property = getCaseInsensitiveProperty(new ClpConfig().setCaseInsensitive(true));
        assertTrue((Boolean) property.getDefaultValue());
    }

    private static PropertyMetadata<?> getCaseInsensitiveProperty(ClpConfig config)
    {
        ClpSessionProperties sessionProperties = new ClpSessionProperties(config);
        PropertyMetadata<?> property = sessionProperties.getSessionProperties().stream()
                .filter(propertyMetadata -> CASE_INSENSITIVE.equals(propertyMetadata.getName()))
                .findFirst()
                .orElseThrow(() -> new AssertionError("case_insensitive session property not registered"));
        assertEquals(property.getJavaType(), Boolean.class);
        return property;
    }
}
