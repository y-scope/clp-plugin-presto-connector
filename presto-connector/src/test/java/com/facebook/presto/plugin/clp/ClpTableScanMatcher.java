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
import com.facebook.presto.cost.StatsProvider;
import com.facebook.presto.metadata.Metadata;
import com.facebook.presto.spi.ColumnHandle;
import com.facebook.presto.spi.plan.PlanNode;
import com.facebook.presto.spi.plan.TableScanNode;
import com.facebook.presto.spi.relation.VariableReferenceExpression;
import com.facebook.presto.sql.planner.assertions.MatchResult;
import com.facebook.presto.sql.planner.assertions.Matcher;
import com.facebook.presto.sql.planner.assertions.PlanMatchPattern;
import com.facebook.presto.sql.planner.assertions.SymbolAliases;
import com.facebook.presto.sql.tree.SymbolReference;

import java.util.HashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static com.facebook.presto.common.Utils.checkState;
import static com.facebook.presto.sql.planner.assertions.MatchResult.NO_MATCH;
import static com.facebook.presto.sql.planner.assertions.MatchResult.match;
import static com.facebook.presto.sql.planner.assertions.PlanMatchPattern.node;

/**
 * Plan-assertion matcher for CLP table scans: matches a {@link TableScanNode} whose layout handle
 * equals the expected one (including kqlQuery, metadataSql, and queryConfig) and whose assignments
 * cover exactly the expected column handles.
 */
final class ClpTableScanMatcher
        implements Matcher
{
    private final ClpTableLayoutHandle expectedLayoutHandle;
    private final Set<ColumnHandle> expectedColumns;

    private ClpTableScanMatcher(ClpTableLayoutHandle expectedLayoutHandle, Set<ColumnHandle> expectedColumns)
    {
        this.expectedLayoutHandle = expectedLayoutHandle;
        this.expectedColumns = expectedColumns;
    }

    static PlanMatchPattern clpTableScanPattern(ClpTableLayoutHandle layoutHandle, Set<ColumnHandle> columns)
    {
        return node(TableScanNode.class).with(new ClpTableScanMatcher(layoutHandle, columns));
    }

    @Override
    public boolean shapeMatches(PlanNode node)
    {
        return node instanceof TableScanNode;
    }

    @Override
    public MatchResult detailMatches(
            PlanNode node,
            StatsProvider stats,
            Session session,
            Metadata metadata,
            SymbolAliases symbolAliases)
    {
        checkState(shapeMatches(node), "Plan testing framework error: shapeMatches returned false");
        TableScanNode tableScanNode = (TableScanNode) node;
        Optional<?> layout = tableScanNode.getTable().getLayout();
        if (!layout.isPresent()) {
            return NO_MATCH;
        }
        ClpTableLayoutHandle actualLayoutHandle = (ClpTableLayoutHandle) layout.get();

        // Check layout handle
        if (!expectedLayoutHandle.equals(actualLayoutHandle)) {
            return NO_MATCH;
        }

        // Check assignments contain expected columns
        Map<VariableReferenceExpression, ColumnHandle> actualAssignments = tableScanNode.getAssignments();
        Set<ColumnHandle> actualColumns = new HashSet<>(actualAssignments.values());

        if (!expectedColumns.equals(actualColumns)) {
            return NO_MATCH;
        }

        SymbolAliases.Builder aliasesBuilder = SymbolAliases.builder();
        for (VariableReferenceExpression variable : tableScanNode.getOutputVariables()) {
            aliasesBuilder.put(variable.getName(), new SymbolReference(variable.getName()));
        }

        return match(aliasesBuilder.build());
    }
}
