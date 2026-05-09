package com.facebook.presto.plugin.clp.split.filter;

import static com.facebook.presto.plugin.clp.ClpConnectorFactory.CONNECTOR_NAME;
import static java.lang.String.format;
import static java.util.UUID.randomUUID;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertThrows;
import static org.testng.Assert.assertTrue;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.URISyntaxException;
import java.net.URL;
import java.nio.file.Paths;
import java.util.Set;

import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.SchemaTableName;
import com.google.common.collect.ImmutableSet;
import org.testng.annotations.BeforeMethod;
import org.testng.annotations.Test;

import com.facebook.presto.plugin.clp.ClpConfig;

@Test(singleThreaded = true)
public class TestClpSplitFilterConfigCommon {
    private String filterConfigPath;

    @BeforeMethod
    public void setUp() throws IOException, URISyntaxException {
        URL resource = getClass().getClassLoader().getResource("test-mysql-split-filter.json");
        if (resource == null) {
            throw new FileNotFoundException("test-mysql-split-filter.json not found in resources");
        }

        filterConfigPath = Paths.get(resource.toURI()).toAbsolutePath().toString();
    }

    @Test
    public void checkRequiredFilters() {
        ClpConfig config = new ClpConfig();
        config.setSplitFilterConfig(filterConfigPath);
        ClpMySqlSplitFilterProvider filterProvider = new ClpMySqlSplitFilterProvider(config);
        Set<String> testTableScopeSet = ImmutableSet.of(
                format("%s.%s", CONNECTOR_NAME, new SchemaTableName("default", "table_1"))
        );
        assertThrows(
                PrestoException.class,
                () -> filterProvider.checkContainsRequiredFilters(
                        testTableScopeSet,
                        "(\"level\" >= 1 AND \"level\" <= 3)"
                )
        );
        filterProvider.checkContainsRequiredFilters(
                testTableScopeSet,
                "(\"msg.timestamp\" > 1234 AND \"msg.timestamp\" < 5678)"
        );
    }

    @Test
    public void getFilterNames() {
        ClpConfig config = new ClpConfig();
        config.setSplitFilterConfig(filterConfigPath);
        ClpMySqlSplitFilterProvider filterProvider = new ClpMySqlSplitFilterProvider(config);
        Set<String> catalogFilterNames = filterProvider.getColumnNames("clp");
        assertEquals(ImmutableSet.of("level"), catalogFilterNames);
        Set<String> schemaFilterNames = filterProvider.getColumnNames("clp.default");
        assertEquals(ImmutableSet.of("level", "author"), schemaFilterNames);
        Set<String> tableFilterNames = filterProvider.getColumnNames("clp.default.table_1");
        assertEquals(
                ImmutableSet.of("level", "author", "msg.timestamp", "file_name"),
                tableFilterNames
        );
    }

    @Test
    public void handleEmptyAndInvalidSplitFilterConfig() {
        ClpConfig config = new ClpConfig();

        // Empty config
        ClpMySqlSplitFilterProvider filterProvider = new ClpMySqlSplitFilterProvider(config);
        assertTrue(filterProvider.getColumnNames("clp").isEmpty());
        assertTrue(filterProvider.getColumnNames("abc.xyz").isEmpty());
        assertTrue(filterProvider.getColumnNames("abc.opq.xyz").isEmpty());

        // Invalid config
        config.setSplitFilterConfig(randomUUID().toString());
        assertThrows(PrestoException.class, () -> new ClpMySqlSplitFilterProvider(config));
    }
}
