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
package com.facebook.presto.plugin.clp.optimization;

import com.facebook.airlift.log.Logger;
import com.facebook.presto.plugin.clp.ClpExpression;
import com.facebook.presto.plugin.clp.ClpTableHandle;
import com.facebook.presto.plugin.clp.ClpTableLayoutHandle;
import com.facebook.presto.plugin.clp.split.filter.ClpSplitFilterProvider;
import com.facebook.presto.spi.ColumnHandle;
import com.facebook.presto.spi.ConnectorPlanOptimizer;
import com.facebook.presto.spi.ConnectorPlanRewriter;
import com.facebook.presto.spi.ConnectorSession;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.TableHandle;
import com.facebook.presto.spi.VariableAllocator;
import com.facebook.presto.spi.function.FunctionMetadataManager;
import com.facebook.presto.spi.function.StandardFunctionResolution;
import com.facebook.presto.spi.plan.FilterNode;
import com.facebook.presto.spi.plan.PlanNode;
import com.facebook.presto.spi.plan.PlanNodeIdAllocator;
import com.facebook.presto.spi.plan.TableScanNode;
import com.facebook.presto.spi.relation.CallExpression;
import com.facebook.presto.spi.relation.ConstantExpression;
import com.facebook.presto.spi.relation.RowExpression;
import com.facebook.presto.spi.relation.SpecialFormExpression;
import com.facebook.presto.spi.relation.VariableReferenceExpression;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import com.google.common.collect.ImmutableSet;
import io.airlift.slice.Slice;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.TreeMap;

import static com.facebook.presto.common.type.BooleanType.BOOLEAN;
import static com.facebook.presto.plugin.clp.ClpConnectorFactory.CONNECTOR_NAME;
import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_INVALID_QUERY_CONFIG;
import static com.facebook.presto.plugin.clp.ClpSessionProperties.CASE_INSENSITIVE;
import static com.facebook.presto.spi.ConnectorPlanRewriter.rewriteWith;
import static com.facebook.presto.spi.relation.SpecialFormExpression.Form.AND;
import static java.lang.String.format;
import static java.util.Locale.ENGLISH;
import static java.util.Objects.requireNonNull;

public class ClpComputePushDown
        implements ConnectorPlanOptimizer
{
    public static final String CLP_QUERY_CONFIG_FUNCTION_NAME = "CLP_QUERY_CONFIG";

    private static final Logger log = Logger.get(ClpComputePushDown.class);
    private static final Map<String, QueryConfigValueType> SUPPORTED_QUERY_CONFIG_KEYS =
            ImmutableMap.of(CASE_INSENSITIVE, QueryConfigValueType.BOOLEAN);

    private final FunctionMetadataManager functionManager;
    private final StandardFunctionResolution functionResolution;
    private final ClpSplitFilterProvider splitFilterProvider;

    public ClpComputePushDown(FunctionMetadataManager functionManager, StandardFunctionResolution functionResolution, ClpSplitFilterProvider splitFilterProvider)
    {
        this.functionManager = requireNonNull(functionManager, "functionManager is null");
        this.functionResolution = requireNonNull(functionResolution, "functionResolution is null");
        this.splitFilterProvider = requireNonNull(splitFilterProvider, "splitFilterProvider is null");
    }

    @Override
    public PlanNode optimize(PlanNode maxSubplan, ConnectorSession session, VariableAllocator variableAllocator, PlanNodeIdAllocator idAllocator)
    {
        Rewriter rewriter = new Rewriter(idAllocator);
        PlanNode optimizedPlanNode = rewriteWith(rewriter, maxSubplan);

        // Throw exception if any required split filters are missing
        if (!rewriter.tableScopeSet.isEmpty() && !rewriter.hasVisitedFilter) {
            splitFilterProvider.checkContainsRequiredFilters(rewriter.tableScopeSet, "");
        }
        return optimizedPlanNode;
    }

    private class Rewriter
            extends ConnectorPlanRewriter<Void>
    {
        private final PlanNodeIdAllocator idAllocator;
        private final Set<String> tableScopeSet;
        private boolean hasVisitedFilter;

        public Rewriter(PlanNodeIdAllocator idAllocator)
        {
            this.idAllocator = idAllocator;
            hasVisitedFilter = false;
            tableScopeSet = new HashSet<>();
        }

        @Override
        public PlanNode visitTableScan(TableScanNode node, RewriteContext<Void> context)
        {
            TableHandle tableHandle = node.getTable();
            ClpTableHandle clpTableHandle = (ClpTableHandle) tableHandle.getConnectorHandle();
            tableScopeSet.add(format("%s.%s", CONNECTOR_NAME, clpTableHandle.getSchemaTableName()));
            return super.visitTableScan(node, context);
        }

        @Override
        public PlanNode visitFilter(FilterNode node, RewriteContext<Void> context)
        {
            if (!(node.getSource() instanceof TableScanNode)) {
                return node;
            }

            return processFilter(node, (TableScanNode) node.getSource());
        }

        private PlanNode processFilter(FilterNode filterNode, TableScanNode tableScanNode)
        {
            hasVisitedFilter = true;

            TableHandle tableHandle = tableScanNode.getTable();
            ClpTableHandle clpTableHandle = (ClpTableHandle) tableHandle.getConnectorHandle();

            String tableScope = CONNECTOR_NAME + "." + clpTableHandle.getSchemaTableName().toString();
            Map<VariableReferenceExpression, ColumnHandle> assignments = tableScanNode.getAssignments();

            Map<String, String> queryConfig = new TreeMap<>();
            Optional<RowExpression> strippedPredicate = extractQueryConfig(filterNode.getPredicate(), queryConfig);

            Optional<String> kqlQuery = Optional.empty();
            Optional<String> metadataSqlQuery = Optional.empty();
            Optional<RowExpression> remainingPredicate = Optional.empty();
            if (strippedPredicate.isPresent()) {
                ClpExpression clpExpression = strippedPredicate.get().accept(
                        new ClpFilterToKqlConverter(
                                functionResolution,
                                functionManager,
                                assignments,
                                splitFilterProvider.getColumnNames(tableScope)),
                        null);
                kqlQuery = clpExpression.getPushDownExpression();
                metadataSqlQuery = clpExpression.getMetadataSqlQuery();
                remainingPredicate = clpExpression.getRemainingExpression();
            }

            // Perform required metadata filter checks before handling the KQL query (if kqlQuery
            // isn't present, we'll return early, skipping subsequent checks).
            splitFilterProvider.checkContainsRequiredFilters(ImmutableSet.of(tableScope), metadataSqlQuery.orElse(""));
            boolean hasMetadataFilter = metadataSqlQuery.isPresent() && !metadataSqlQuery.get().isEmpty();
            if (hasMetadataFilter) {
                metadataSqlQuery = Optional.of(splitFilterProvider.remapSplitFilterPushDownExpression(tableScope, metadataSqlQuery.get()));
                log.debug("Metadata SQL query: %s", metadataSqlQuery.get());
            }

            if (kqlQuery.isPresent() || hasMetadataFilter || !queryConfig.isEmpty()) {
                if (kqlQuery.isPresent()) {
                    log.debug("KQL query: %s", kqlQuery.get());
                }

                ClpTableLayoutHandle layoutHandle = new ClpTableLayoutHandle(clpTableHandle, kqlQuery, metadataSqlQuery, queryConfig);
                TableHandle newTableHandle = new TableHandle(
                        tableHandle.getConnectorId(),
                        clpTableHandle,
                        tableHandle.getTransaction(),
                        Optional.of(layoutHandle));

                tableScanNode = new TableScanNode(
                        tableScanNode.getSourceLocation(),
                        idAllocator.getNextId(),
                        newTableHandle,
                        tableScanNode.getOutputVariables(),
                        tableScanNode.getAssignments(),
                        tableScanNode.getTableConstraints(),
                        tableScanNode.getCurrentConstraint(),
                        tableScanNode.getEnforcedConstraint(),
                        tableScanNode.getCteMaterializationInfo());
            }

            if (remainingPredicate.isPresent()) {
                // Not all predicate pushed down, need new FilterNode
                return new FilterNode(
                        filterNode.getSourceLocation(),
                        idAllocator.getNextId(),
                        tableScanNode,
                        remainingPredicate.get());
            }
            else {
                return tableScanNode;
            }
        }

        /**
         * Extracts {@code CLP_QUERY_CONFIG(key, value)} marker calls from the top-level AND
         * conjuncts of the given predicate into {@code queryConfig}, and returns the predicate
         * rebuilt from the remaining conjuncts (empty if the markers were the entire predicate).
         * <p>
         * The markers let users set per-query connector config inside the query text (e.g. when
         * middleware strips session properties). Markers anywhere other than a top-level conjunct
         * (e.g. under OR or NOT) are left in place and fail at execution time with the placeholder
         * function's error message.
         * <p>
         * Multiple markers with distinct keys are supported. Repeating the SAME key in one query
         * is unsupported and its behavior is unspecified (currently the last conjunct wins, but
         * callers must not rely on this).
         */
        private Optional<RowExpression> extractQueryConfig(RowExpression predicate, Map<String, String> queryConfig)
        {
            ImmutableList.Builder<RowExpression> conjunctsBuilder = ImmutableList.builder();
            collectConjuncts(predicate, conjunctsBuilder);

            boolean foundMarker = false;
            List<RowExpression> remainingConjuncts = new ArrayList<>();
            for (RowExpression conjunct : conjunctsBuilder.build()) {
                if (tryParseQueryConfigCall(conjunct, queryConfig)) {
                    foundMarker = true;
                }
                else {
                    remainingConjuncts.add(conjunct);
                }
            }

            if (!foundMarker) {
                // Keep the original predicate shape so the generated KQL is unchanged when the
                // feature isn't used.
                return Optional.of(predicate);
            }

            return remainingConjuncts.stream()
                    .reduce((left, right) -> new SpecialFormExpression(AND, BOOLEAN, left, right));
        }

        private void collectConjuncts(RowExpression expression, ImmutableList.Builder<RowExpression> conjuncts)
        {
            if (expression instanceof SpecialFormExpression && ((SpecialFormExpression) expression).getForm() == AND) {
                for (RowExpression argument : ((SpecialFormExpression) expression).getArguments()) {
                    collectConjuncts(argument, conjuncts);
                }
            }
            else {
                conjuncts.add(expression);
            }
        }

        /**
         * If the given expression is a {@code CLP_QUERY_CONFIG(key, value)} call, validates it,
         * records the key/value pair in {@code queryConfig}, and returns true. Returns false for
         * any other expression.
         * <p>
         * The key must be a non-null varchar literal, matched case-insensitively. The value must
         * be a literal whose type matches the key's {@link QueryConfigValueType} (e.g. an
         * unquoted boolean literal for a BOOLEAN key — the string {@code 'true'} is rejected).
         * Computed expressions (e.g. column references or function calls) fail the query with
         * {@code CLP_INVALID_QUERY_CONFIG}.
         */
        private boolean tryParseQueryConfigCall(RowExpression expression, Map<String, String> queryConfig)
        {
            if (!(expression instanceof CallExpression)) {
                return false;
            }
            CallExpression call = (CallExpression) expression;
            String functionName = functionManager.getFunctionMetadata(call.getFunctionHandle()).getName().getObjectName().toUpperCase(ENGLISH);
            if (!functionName.equals(CLP_QUERY_CONFIG_FUNCTION_NAME)) {
                return false;
            }

            if (call.getArguments().size() != 2
                    || !(call.getArguments().get(0) instanceof ConstantExpression)
                    || !(call.getArguments().get(1) instanceof ConstantExpression)) {
                throw new PrestoException(CLP_INVALID_QUERY_CONFIG,
                        CLP_QUERY_CONFIG_FUNCTION_NAME + " requires a varchar literal key and a literal value, e.g. CLP_QUERY_CONFIG('case_insensitive', true)");
            }

            Object keyValue = ((ConstantExpression) call.getArguments().get(0)).getValue();
            Object valueValue = ((ConstantExpression) call.getArguments().get(1)).getValue();
            if (!(keyValue instanceof Slice)) {
                throw new PrestoException(CLP_INVALID_QUERY_CONFIG,
                        CLP_QUERY_CONFIG_FUNCTION_NAME + " keys must be non-null varchar literals");
            }

            String key = ((Slice) keyValue).toStringUtf8().toLowerCase(ENGLISH);
            QueryConfigValueType valueType = SUPPORTED_QUERY_CONFIG_KEYS.get(key);
            if (valueType == null) {
                throw new PrestoException(CLP_INVALID_QUERY_CONFIG,
                        format("Unsupported %s key: '%s'. Supported keys: %s", CLP_QUERY_CONFIG_FUNCTION_NAME, key, SUPPORTED_QUERY_CONFIG_KEYS.keySet()));
            }

            queryConfig.put(key, valueType.toConfigString(valueValue, key));
            return true;
        }
    }

    /**
     * Value type of a supported {@code CLP_QUERY_CONFIG} key, used to validate the value literal
     * on the coordinator so workers can consume it without re-validating.
     */
    private enum QueryConfigValueType
    {
        BOOLEAN("a boolean literal (true or false)"),
        STRING("a varchar literal"),
        INTEGER("a bigint literal"),
        FLOAT("a double literal");

        private final String expectation;

        QueryConfigValueType(String expectation)
        {
            this.expectation = expectation;
        }

        /**
         * Converts a value literal to its canonical string form for the query config map,
         * enforcing that the literal's type matches this key type — e.g. a BOOLEAN key only
         * accepts an unquoted boolean literal, not the string {@code 'true'}.
         */
        String toConfigString(Object valueLiteral, String key)
        {
            switch (this) {
                case BOOLEAN:
                    if (valueLiteral instanceof Boolean) {
                        return valueLiteral.toString();
                    }
                    break;
                case STRING:
                    if (valueLiteral instanceof Slice) {
                        return ((Slice) valueLiteral).toStringUtf8();
                    }
                    break;
                case INTEGER:
                    if (valueLiteral instanceof Long) {
                        return valueLiteral.toString();
                    }
                    break;
                case FLOAT:
                    if (valueLiteral instanceof Double || valueLiteral instanceof Long) {
                        return valueLiteral.toString();
                    }
                    break;
            }
            throw new PrestoException(CLP_INVALID_QUERY_CONFIG,
                    format("Invalid value for %s key '%s'. Expected %s", CLP_QUERY_CONFIG_FUNCTION_NAME, key, expectation));
        }
    }
}
