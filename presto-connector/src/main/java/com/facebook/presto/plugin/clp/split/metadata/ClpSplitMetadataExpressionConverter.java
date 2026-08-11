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
package com.facebook.presto.plugin.clp.split.metadata;

import com.facebook.presto.common.function.OperatorType;
import com.facebook.presto.common.type.Type;
import com.facebook.presto.spi.function.FunctionMetadataManager;
import com.facebook.presto.plugin.clp.split.metadata.ClpSplitMetadataConfig.RangeBounds;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.SchemaTableName;
import com.facebook.presto.spi.function.FunctionMetadata;
import com.facebook.presto.spi.function.StandardFunctionResolution;
import com.facebook.presto.spi.relation.CallExpression;
import com.facebook.presto.spi.relation.ConstantExpression;
import com.facebook.presto.spi.relation.InputReferenceExpression;
import com.facebook.presto.spi.relation.LambdaDefinitionExpression;
import com.facebook.presto.spi.relation.RowExpression;
import com.facebook.presto.spi.relation.RowExpressionVisitor;
import com.facebook.presto.spi.relation.SpecialFormExpression;
import com.facebook.presto.spi.relation.VariableReferenceExpression;
import io.airlift.slice.Slice;

import java.util.HashSet;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_MANDATORY_SPLIT_FILTER_NOT_VALID;
import static com.facebook.presto.plugin.clp.ClpErrorCode.CLP_PUSHDOWN_UNSUPPORTED_EXPRESSION;
import static java.lang.String.format;
import static java.util.Objects.requireNonNull;

/**
 * Renders a predicate as a SQL condition over a split provider's metadata columns, so that a
 * split which cannot hold a matching row is never listed.
 * <p>
 * A predicate on a data column bounded by a range (see {@link ClpSplitMetadataConfig}) is rewritten
 * against those bounds: a split qualifies when its range overlaps the values that the predicate
 * admits.
 * A predicate naming anything else is not translatable and is reported as such, leaving the caller
 * to apply it after the scan.
 */
public class ClpSplitMetadataExpressionConverter
        implements RowExpressionVisitor<String, Void>
{
    private final StandardFunctionResolution functionResolution;
    private final FunctionMetadataManager functionManager;
    private final ClpSplitMetadataConfig metadataConfig;
    private final SchemaTableName table;
    private final Set<String> filteredColumns = new HashSet<>();

    public ClpSplitMetadataExpressionConverter(
            StandardFunctionResolution functionResolution,
            FunctionMetadataManager functionManager,
            ClpSplitMetadataConfig metadataConfig,
            SchemaTableName table)
    {
        this.functionResolution = requireNonNull(functionResolution, "functionResolution is null");
        this.functionManager = requireNonNull(functionManager, "functionManager is null");
        this.metadataConfig = requireNonNull(metadataConfig, "metadataConfig is null");
        this.table = requireNonNull(table, "table is null");
    }

    /**
     * @param predicate
     * @return {@code predicate} as a SQL condition.
     * @throws PrestoException if a column the configuration marks as required is left unfiltered,
     * which would otherwise scan every split.
     */
    public String toSqlCondition(RowExpression predicate)
    {
        filteredColumns.clear();
        String sql = predicate.accept(this, null);

        Set<String> missing = new HashSet<>(metadataConfig.getRequiredColumns(table));
        missing.removeAll(filteredColumns);
        if (false == missing.isEmpty()) {
            throw new PrestoException(CLP_MANDATORY_SPLIT_FILTER_NOT_VALID,
                    format("Query on %s must filter on %s", table, missing));
        }
        return sql;
    }

    @Override
    public String visitCall(CallExpression node, Void context)
    {
        if (functionResolution.isNotFunction(node.getFunctionHandle())) {
            return format("NOT (%s)", node.getArguments().get(0).accept(this, null));
        }

        FunctionMetadata metadata = functionManager.getFunctionMetadata(node.getFunctionHandle());
        Optional<OperatorType> operator = metadata.getOperatorType();
        if (false == operator.isPresent()) {
            throw unsupported(node);
        }

        if (OperatorType.NEGATION == operator.get()) {
            return "-" + node.getArguments().get(0).accept(this, null);
        }
        if (false == operator.get().isComparisonOperator()
                || OperatorType.IS_DISTINCT_FROM == operator.get()) {
            throw unsupported(node);
        }

        RowExpression left = node.getArguments().get(0);
        String literal = node.getArguments().get(1).accept(this, null);
        if (false == (left instanceof VariableReferenceExpression)) {
            throw unsupported(node);
        }

        String column = ((VariableReferenceExpression) left).getName();
        filteredColumns.add(column);

        Optional<RangeBounds> bounds = metadataConfig.getRangeBounds(table, column);
        if (bounds.isPresent()) {
            return againstBounds(node, bounds.get(), operator.get(), literal);
        }
        return format("%s %s %s", column, operator.get().getOperator(), literal);
    }

    /**
     * Rewrites a comparison on a range-bounded data column against the metadata columns holding
     * those bounds. A split qualifies when its range could contain a matching row, so the
     * comparison flips: {@code c >= v} keeps splits whose upper bound reaches {@code v}, and
     * {@code c <= v} keeps splits whose lower bound falls below it.
     */
    private String againstBounds(
            CallExpression node,
            RangeBounds bounds,
            OperatorType operator,
            String literal)
    {
        switch (operator) {
            case GREATER_THAN:
            case GREATER_THAN_OR_EQUAL:
                return bounds.getUpper()
                        .map(upper -> format("%s %s %s", upper, operator.getOperator(), literal))
                        .orElseThrow(() -> unsupported(node));
            case LESS_THAN:
            case LESS_THAN_OR_EQUAL:
                return bounds.getLower()
                        .map(lower -> format("%s %s %s", lower, operator.getOperator(), literal))
                        .orElseThrow(() -> unsupported(node));
            case EQUAL:
                if (bounds.getLower().isPresent() && bounds.getUpper().isPresent()) {
                    return format("(%s <= %s) AND (%s >= %s)",
                            bounds.getLower().get(), literal, bounds.getUpper().get(), literal);
                }
                return bounds.getLower()
                        .map(lower -> format("%s <= %s", lower, literal))
                        .orElseGet(() -> format("%s >= %s", bounds.getUpper().get(), literal));
            default:
                throw unsupported(node);
        }
    }

    @Override
    public String visitSpecialForm(SpecialFormExpression node, Void context)
    {
        switch (node.getForm()) {
            case AND:
            case OR:
                return node.getArguments().stream()
                        .map(argument -> "(" + argument.accept(this, context) + ")")
                        .collect(Collectors.joining(" " + node.getForm().name() + " "));
            case IS_NULL:
                return format("(%s IS NULL)", node.getArguments().get(0).accept(this, context));
            default:
                throw unsupported(node);
        }
    }

    @Override
    public String visitConstant(ConstantExpression node, Void context)
    {
        Object value = node.getValue();
        if (null == value) {
            return "NULL";
        }
        if (value instanceof Slice) {
            return "'" + ((Slice) value).toStringUtf8().replace("'", "''") + "'";
        }
        return value.toString();
    }

    @Override
    public String visitVariableReference(VariableReferenceExpression node, Void context)
    {
        return node.getName();
    }

    @Override
    public String visitInputReference(InputReferenceExpression node, Void context)
    {
        throw unsupported(node);
    }

    @Override
    public String visitLambda(LambdaDefinitionExpression node, Void context)
    {
        throw unsupported(node);
    }

    private static PrestoException unsupported(RowExpression node)
    {
        return new PrestoException(CLP_PUSHDOWN_UNSUPPORTED_EXPRESSION,
                "Cannot express as a split metadata filter: " + node);
    }

    /** @return The type a metadata column carries, for callers coercing literals. */
    public Optional<Type> getColumnType(String column)
    {
        return Optional.ofNullable(metadataConfig.getMetadataColumns(table).get(column));
    }
}
