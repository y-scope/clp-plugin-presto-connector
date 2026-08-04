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

import com.facebook.presto.spi.ErrorCodeSupplier;
import com.facebook.presto.spi.PrestoException;

import java.util.ServiceConfigurationError;
import java.util.ServiceLoader;
import java.util.TreeMap;
import java.util.function.Function;

/**
 * Resolves a provider factory registered via {@link ServiceLoader} by its configured name.
 */
final class ClpProviderResolver
{
    private ClpProviderResolver()
    {
    }

    /**
     * Finds the single factory whose name matches {@code configuredName}, case-insensitively.
     *
     * @param factoryType the SPI interface to load
     * @param nameGetter extracts a factory's selector name
     * @param configuredName the value of {@code propertyName} in the catalog properties
     * @param propertyName the catalog property being resolved, for error messages
     * @param errorCode the error code to raise when resolution fails
     * @return the matching factory
     * @throws PrestoException if no factory matches, if the name is blank, or if two factories
     *         claim the same name
     */
    static <F> F resolve(
            Class<F> factoryType,
            Function<F, String> nameGetter,
            String configuredName,
            String propertyName,
            ErrorCodeSupplier errorCode)
    {
        if (null == configuredName || configuredName.trim().isEmpty()) {
            throw new PrestoException(errorCode, propertyName + " is not set");
        }
        String wanted = configuredName.trim();

        // Load through the class' own ClassLoader rather than the thread-context one: Presto loads
        // each plugin in an isolated PluginClassLoader, and the context ClassLoader during module
        // setup isn't guaranteed to be it.
        ServiceLoader<F> loader = ServiceLoader.load(factoryType, factoryType.getClassLoader());

        // TreeMap with a case-insensitive comparator so lookup and duplicate detection agree on
        // what "the same name" means.
        TreeMap<String, F> byName = new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        try {
            for (F factory : loader) {
                String name = nameGetter.apply(factory);
                if (null == name || name.trim().isEmpty()) {
                    throw new PrestoException(
                            errorCode,
                            factory.getClass().getName() + " returned a blank provider name");
                }
                F previous = byName.put(name.trim(), factory);
                if (null != previous) {
                    throw new PrestoException(
                            errorCode,
                            String.format(
                                    "Provider name '%s' is claimed by both %s and %s; remove one from the plugin's classpath",
                                    name.trim(),
                                    previous.getClass().getName(),
                                    factory.getClass().getName()));
                }
            }
        }
        catch (ServiceConfigurationError e) {
            throw new PrestoException(
                    errorCode,
                    "Failed to load " + factoryType.getSimpleName() + " implementations: " + e.getMessage(),
                    e);
        }

        F factory = byName.get(wanted);
        if (null == factory) {
            throw new PrestoException(
                    errorCode,
                    String.format(
                            "Unsupported %s: '%s'. Registered providers: %s",
                            propertyName,
                            wanted,
                            byName.isEmpty()
                                    ? "(none found on the plugin classpath)"
                                    : String.join(", ", byName.keySet())));
        }
        return factory;
    }
}
