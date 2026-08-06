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
import com.google.common.collect.ImmutableList;

import javax.inject.Inject;

import java.util.List;

import static com.facebook.presto.spi.session.PropertyMetadata.booleanProperty;

/**
 * Session properties for the CLP connector. Users can override them per
 * session, e.g. {@code SET SESSION clp.case_insensitive = true;}. The
 * properties are forwarded to native workers as part of the per-catalog
 * session config, so they don't need to be carried on splits or table
 * handles.
 */
public class ClpSessionProperties
{
    public static final String CASE_INSENSITIVE = "case_insensitive";

    private final List<PropertyMetadata<?>> sessionProperties;

    @Inject
    public ClpSessionProperties(ClpConfig config)
    {
        sessionProperties = ImmutableList.of(
                booleanProperty(
                        CASE_INSENSITIVE,
                        "Match string values case-insensitively in filters pushed down to CLP",
                        config.isCaseInsensitive(),
                        false));
    }

    public List<PropertyMetadata<?>> getSessionProperties()
    {
        return sessionProperties;
    }
}
