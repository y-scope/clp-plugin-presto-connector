package com.facebook.presto.plugin.clp;

import static com.facebook.presto.testing.TestingSession.testSessionBuilder;

import java.net.URI;
import java.util.Map;
import java.util.Optional;
import java.util.function.BiFunction;

import com.facebook.airlift.log.Logger;
import com.facebook.presto.Session;
import com.facebook.presto.tests.DistributedQueryRunner;
import com.google.common.collect.ImmutableMap;

public class ClpQueryRunner {
    private static final Logger log = Logger.get(ClpQueryRunner.class);

    public static final String CLP_CATALOG = "clp";
    public static final String CLP_CONNECTOR = CLP_CATALOG;
    public static final int DEFAULT_NUM_OF_WORKERS = 1;
    public static final String DEFAULT_SCHEMA = "default";

    public static DistributedQueryRunner createQueryRunner(
            String metadataDbUrl,
            String metadataDbUser,
            String metadataDbPassword,
            String metadataDbTablePrefix,
            Optional<Integer> workerCount,
            Optional<BiFunction<Integer, URI, Process>> externalWorkerLauncher
    )
            throws Exception {
        log.info("Creating CLP query runner with default session");
        return createQueryRunner(
                createDefaultSession(),
                metadataDbUrl,
                metadataDbUser,
                metadataDbPassword,
                metadataDbTablePrefix,
                workerCount,
                externalWorkerLauncher
        );
    }

    public static DistributedQueryRunner createQueryRunner(
            Session session,
            String metadataDbUrl,
            String metadataDbUser,
            String metadataDbPassword,
            String metadataDbTablePrefix,
            Optional<Integer> workerCount,
            Optional<BiFunction<Integer, URI, Process>> externalWorkerLauncher
    )
            throws Exception {
        DistributedQueryRunner clpQueryRunner = DistributedQueryRunner.builder(session)
                .setNodeCount(workerCount.orElse(DEFAULT_NUM_OF_WORKERS)).setExternalWorkerLauncher(
                        externalWorkerLauncher
                ).build();
        Map<String, String> clpProperties = ImmutableMap.<String, String>builder().put(
                "clp.metadata-provider-type",
                "mysql"
        ).put("clp.metadata-db-url", metadataDbUrl).put("clp.metadata-db-user", metadataDbUser).put(
                "clp.metadata-db-password",
                metadataDbPassword
        ).put("clp.metadata-table-prefix", metadataDbTablePrefix).put(
                "clp.split-provider-type",
                "mysql"
        ).build();

        clpQueryRunner.installPlugin(new ClpPlugin());
        clpQueryRunner.createCatalog(CLP_CATALOG, CLP_CONNECTOR, clpProperties);
        return clpQueryRunner;
    }

    /**
     * Creates a default mock session for query use.
     *
     * @return a default session
     */
    private static Session createDefaultSession() {
        return testSessionBuilder().setCatalog(CLP_CATALOG).setSchema(DEFAULT_SCHEMA).build();
    }

    private ClpQueryRunner() {}
}
