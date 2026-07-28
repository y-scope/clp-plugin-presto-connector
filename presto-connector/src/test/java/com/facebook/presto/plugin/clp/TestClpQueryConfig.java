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

import com.facebook.presto.Session;
import com.facebook.presto.common.transaction.TransactionId;
import com.facebook.presto.cost.PlanNodeStatsEstimate;
import com.facebook.presto.cost.StatsAndCosts;
import com.facebook.presto.metadata.FunctionAndTypeManager;
import com.facebook.presto.plugin.clp.optimization.ClpComputePushDown;
import com.facebook.presto.plugin.clp.split.filter.ClpMySqlSplitFilterProvider;
import com.facebook.presto.plugin.clp.split.filter.ClpSplitFilterProvider;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.SchemaTableName;
import com.facebook.presto.spi.VariableAllocator;
import com.facebook.presto.spi.WarningCollector;
import com.facebook.presto.spi.plan.PlanNode;
import com.facebook.presto.spi.plan.PlanNodeIdAllocator;
import com.facebook.presto.sql.planner.Plan;
import com.facebook.presto.sql.planner.assertions.PlanAssert;
import com.facebook.presto.sql.planner.assertions.PlanMatchPattern;
import com.facebook.presto.sql.relational.FunctionResolution;
import com.facebook.presto.testing.LocalQueryRunner;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import com.google.common.collect.ImmutableSet;
import org.apache.commons.math3.util.Pair;
import org.testng.annotations.AfterMethod;
import org.testng.annotations.BeforeMethod;
import org.testng.annotations.Test;

import java.util.Optional;

import static com.facebook.presto.metadata.FunctionExtractor.extractFunctions;
import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.ARCHIVES_STORAGE_DIRECTORY_BASE;
import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.METADATA_DB_PASSWORD;
import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.METADATA_DB_TABLE_PREFIX;
import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.METADATA_DB_URL_TEMPLATE;
import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.METADATA_DB_USER;
import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.getDbHandle;
import static com.facebook.presto.plugin.clp.ClpMetadataDbSetUp.setupMetadata;
import static com.facebook.presto.plugin.clp.metadata.ClpSchemaTreeNodeType.Boolean;
import static com.facebook.presto.plugin.clp.metadata.ClpSchemaTreeNodeType.ClpString;
import static com.facebook.presto.plugin.clp.metadata.ClpSchemaTreeNodeType.Float;
import static com.facebook.presto.plugin.clp.metadata.ClpSchemaTreeNodeType.Integer;
import static com.facebook.presto.plugin.clp.metadata.ClpSchemaTreeNodeType.VarString;
import static com.facebook.presto.sql.planner.assertions.PlanMatchPattern.anyTree;
import static com.facebook.presto.sql.planner.assertions.PlanMatchPattern.filter;
import static com.facebook.presto.testing.TestingSession.testSessionBuilder;
import static java.lang.String.format;

@Test(singleThreaded = true)
public class TestClpQueryConfig
        extends TestClpQueryBase
{
    private final Session defaultSession = testSessionBuilder()
            .setCatalog("clp")
            .setSchema(ClpMetadata.DEFAULT_SCHEMA_NAME)
            .build();

    private ClpMetadataDbSetUp.DbHandle dbHandle;
    ClpTableHandle table;

    private LocalQueryRunner localQueryRunner;
    private FunctionAndTypeManager functionAndTypeManager;
    private FunctionResolution functionResolution;
    private ClpSplitFilterProvider splitFilterProvider;
    private PlanNodeIdAllocator planNodeIdAllocator;
    private VariableAllocator variableAllocator;

    @BeforeMethod
    public void setUp()
    {
        dbHandle = getDbHandle("query_config_testdb");
        final String tableName = "test";
        final String tablePath = ARCHIVES_STORAGE_DIRECTORY_BASE + tableName;
        table = new ClpTableHandle(new SchemaTableName("default", tableName), tablePath);

        setupMetadata(dbHandle,
                ImmutableMap.of(
                        tableName,
                        ImmutableList.of(
                                new Pair<>("city.Name", ClpString),
                                new Pair<>("city.Region.Id", Integer),
                                new Pair<>("city.Region.Name", VarString),
                                new Pair<>("fare", Float),
                                new Pair<>("isHoliday", Boolean))));

        localQueryRunner = new LocalQueryRunner(defaultSession);
        localQueryRunner.createCatalog("clp", new ClpConnectorFactory(), ImmutableMap.of(
                "clp.metadata-db-url", format(METADATA_DB_URL_TEMPLATE, dbHandle.getDbPath()),
                "clp.metadata-db-user", METADATA_DB_USER,
                "clp.metadata-db-password", METADATA_DB_PASSWORD,
                "clp.metadata-table-prefix", METADATA_DB_TABLE_PREFIX));
        localQueryRunner.getMetadata().registerBuiltInFunctions(extractFunctions(new ClpPlugin().getFunctions()));
        functionAndTypeManager = localQueryRunner.getMetadata().getFunctionAndTypeManager();
        functionResolution = new FunctionResolution(functionAndTypeManager.getFunctionAndTypeResolver());
        splitFilterProvider = new ClpMySqlSplitFilterProvider(new ClpConfig());
        planNodeIdAllocator = new PlanNodeIdAllocator();
        variableAllocator = new VariableAllocator();
    }

    @AfterMethod
    public void tearDown()
    {
        localQueryRunner.close();
        ClpMetadataDbSetUp.tearDown(dbHandle);
    }

    private PlanNode optimize(Session session, String sql)
    {
        Plan plan = localQueryRunner.createPlan(session, sql, WarningCollector.NOOP);
        ClpComputePushDown optimizer = new ClpComputePushDown(functionAndTypeManager, functionResolution, splitFilterProvider);
        return optimizer.optimize(plan.getRoot(), session.toConnectorSession(), variableAllocator, planNodeIdAllocator);
    }

    private Session transactionSession()
    {
        TransactionId transactionId = localQueryRunner.getTransactionManager().beginTransaction(false);
        return testSessionBuilder().setCatalog("clp").setSchema("default").setTransactionId(transactionId).build();
    }

    private void assertOptimizedPlan(Session session, String sql, PlanMatchPattern pattern)
    {
        Plan plan = localQueryRunner.createPlan(session, sql, WarningCollector.NOOP);
        ClpComputePushDown optimizer = new ClpComputePushDown(functionAndTypeManager, functionResolution, splitFilterProvider);
        PlanNode optimizedPlan = optimizer.optimize(plan.getRoot(), session.toConnectorSession(), variableAllocator, planNodeIdAllocator);
        PlanAssert.assertPlan(
                session,
                localQueryRunner.getMetadata(),
                (node, sourceStats, lookup, s, types) -> PlanNodeStatsEstimate.unknown(),
                new Plan(optimizedPlan, plan.getTypes(), StatsAndCosts.empty()),
                pattern);
    }

    @Test
    public void testQueryConfigWithPushedDownFilter()
    {
        Session session = transactionSession();
        assertOptimizedPlan(
                session,
                "SELECT * FROM test WHERE CLP_QUERY_CONFIG('case_insensitive', 'true') AND isHoliday = true",
                anyTree(
                        ClpTableScanMatcher.clpTableScanPattern(
                                new ClpTableLayoutHandle(
                                        table,
                                        Optional.of("isHoliday: true"),
                                        Optional.empty(),
                                        ImmutableMap.of("case_insensitive", "true")),
                                ImmutableSet.of(city, fare, isHoliday))));
    }

    @Test
    public void testQueryConfigOnlyFilter()
    {
        Session session = transactionSession();
        assertOptimizedPlan(
                session,
                "SELECT * FROM test WHERE CLP_QUERY_CONFIG('case_insensitive', 'true')",
                anyTree(
                        ClpTableScanMatcher.clpTableScanPattern(
                                new ClpTableLayoutHandle(
                                        table,
                                        Optional.empty(),
                                        Optional.empty(),
                                        ImmutableMap.of("case_insensitive", "true")),
                                ImmutableSet.of(city, fare, isHoliday))));
    }

    @Test
    public void testQueryConfigWithRemainingPredicate()
    {
        Session session = transactionSession();
        assertOptimizedPlan(
                session,
                "SELECT * FROM test WHERE CLP_QUERY_CONFIG('case_insensitive', 'false') AND LOWER(city.Name) = 'beijing'",
                anyTree(
                        filter(
                                expression("lower(city.Name) = 'beijing'"),
                                ClpTableScanMatcher.clpTableScanPattern(
                                        new ClpTableLayoutHandle(
                                                table,
                                                Optional.empty(),
                                                Optional.empty(),
                                                ImmutableMap.of("case_insensitive", "false")),
                                        ImmutableSet.of(city, fare, isHoliday)))));
    }

    @Test(expectedExceptions = PrestoException.class, expectedExceptionsMessageRegExp = ".*Unsupported CLP_QUERY_CONFIG key.*")
    public void testQueryConfigUnsupportedKey()
    {
        Session session = transactionSession();
        optimize(session, "SELECT * FROM test WHERE CLP_QUERY_CONFIG('bogus_key', 'true') AND isHoliday = true");
    }

    @Test(expectedExceptions = PrestoException.class, expectedExceptionsMessageRegExp = ".*Invalid value.*")
    public void testQueryConfigInvalidValue()
    {
        Session session = transactionSession();
        optimize(session, "SELECT * FROM test WHERE CLP_QUERY_CONFIG('case_insensitive', 'yes') AND isHoliday = true");
    }

    @Test(expectedExceptions = PrestoException.class, expectedExceptionsMessageRegExp = ".*varchar literal.*")
    public void testQueryConfigNonLiteralArguments()
    {
        Session session = transactionSession();
        optimize(session, "SELECT * FROM test WHERE CLP_QUERY_CONFIG(city.Name, 'true') AND isHoliday = true");
    }

    @Test
    public void testQueryConfigTypedBooleanValue()
    {
        Session session = transactionSession();
        assertOptimizedPlan(
                session,
                "SELECT * FROM test WHERE CLP_QUERY_CONFIG('case_insensitive', true) AND isHoliday = true",
                anyTree(
                        ClpTableScanMatcher.clpTableScanPattern(
                                new ClpTableLayoutHandle(
                                        table,
                                        Optional.of("isHoliday: true"),
                                        Optional.empty(),
                                        ImmutableMap.of("case_insensitive", "true")),
                                ImmutableSet.of(city, fare, isHoliday))));
    }

    @Test
    public void testQueryConfigKeyAndBooleanValueAreCaseInsensitive()
    {
        Session session = transactionSession();
        assertOptimizedPlan(
                session,
                "SELECT * FROM test WHERE CLP_QUERY_CONFIG('CASE_INSENSITIVE', 'TRUE') AND isHoliday = true",
                anyTree(
                        ClpTableScanMatcher.clpTableScanPattern(
                                new ClpTableLayoutHandle(
                                        table,
                                        Optional.of("isHoliday: true"),
                                        Optional.empty(),
                                        ImmutableMap.of("case_insensitive", "true")),
                                ImmutableSet.of(city, fare, isHoliday))));
    }

    @Test
    public void testQueryConfigUnderOrIsNotExtracted()
    {
        Session session = transactionSession();
        // A marker below a top-level AND conjunct is not a per-query config: it stays in the
        // remaining predicate (where it fails at execution time with the placeholder's error) and
        // no config is recorded on the layout handle.
        assertOptimizedPlan(
                session,
                "SELECT * FROM test WHERE CLP_QUERY_CONFIG('case_insensitive', 'true') OR isHoliday = true",
                anyTree(
                        filter(
                                expression("CLP_QUERY_CONFIG('case_insensitive', 'true') OR isHoliday = true"),
                                ClpTableScanMatcher.clpTableScanPattern(
                                        new ClpTableLayoutHandle(table, Optional.empty(), Optional.empty()),
                                        ImmutableSet.of(city, fare, isHoliday)))));
    }
}
