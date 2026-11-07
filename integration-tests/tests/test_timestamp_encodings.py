"""Timestamp marshalling across storage encodings, on the archive and IR paths."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from clp_presto_integration_tests.client import PrestoClient

# How Presto renders the instant that test_3 encodes four ways, and how it is written as a SQL
# literal. Presto renders timestamps with milliseconds; the literal carries none.
_INSTANT = "2025-04-30 08:50:05.000"
_INSTANT_LITERAL = "2025-04-30 08:50:05"


@pytest.mark.archive
def test_every_encoding_marshals_to_one_instant(client: PrestoClient) -> None:
    """
    One instant, four encodings.

    test_3 encodes one instant four ways -- ISO string, float seconds, microseconds and
    nanoseconds -- and all four must read back as the same timestamp.
    """
    rows = client.run("SELECT timestamp_timestamp FROM clp.default.timestamps")
    assert [row[0] for row in rows] == [_INSTANT] * 4


@pytest.mark.ir
def test_ir_timestamps(client: PrestoClient) -> None:
    """The IR path marshals the same encodings, including a record with no timestamp at all."""
    rows = client.run("SELECT timestamp_timestamp FROM clp.default.timestamps_ir ORDER BY 1")
    assert rows == [[_INSTANT], ["2025-12-17 20:23:25.000"], [None]]


@pytest.mark.pushdown
def test_equality_matches_every_encoding(client: PrestoClient) -> None:
    """
    Every encoding denotes the same instant, so equality should match all four records.

    `timestamp` is stored under three physical types, so this only holds once the predicate is
    compared against the projected column instead of the raw encodings -- see
    test_mixed_type_timestamp_is_not_pushed_down.
    """
    matched = client.scalar(
        "SELECT COUNT(*) FROM clp.default.timestamps"
        f" WHERE timestamp_timestamp = TIMESTAMP '{_INSTANT_LITERAL}'"
    )
    assert matched == 4


@pytest.mark.pushdown
@pytest.mark.ir
def test_ir_range_pushdown(client: PrestoClient) -> None:
    """The one record before the threshold should survive the filter."""
    matched = client.scalar(
        "SELECT COUNT(*) FROM clp.default.timestamps_ir"
        " WHERE timestamp_timestamp < TIMESTAMP '2025-06-01 00:00:00'"
    )
    assert matched == 1


@pytest.mark.pushdown
@pytest.mark.archive
def test_mixed_type_timestamp_is_not_pushed_down(client: PrestoClient) -> None:
    """
    A filter on a mixed-type timestamp column stays in the plan.

    CLP stores `timestamp` as a timestamp, an integer, and a float, and a pushed-down comparison
    only sees the raw encodings, so the connector translates no KQL for such a column: the table
    layout carries no filter and Presto applies the predicate to the projected values itself.
    """
    plan = client.run(
        "EXPLAIN SELECT COUNT(*) FROM clp.default.timestamps"
        f" WHERE timestamp_timestamp = TIMESTAMP '{_INSTANT_LITERAL}'"
    )
    assert len(plan) == 1
    assert "kqlQuery=Optional.empty" in plan[0][0]


@pytest.mark.pushdown
@pytest.mark.archive
def test_single_encoding_timestamp_is_still_pushed_down(client: PrestoClient) -> None:
    """A timestamp column whose field was stored one way keeps its filter inside CLP."""
    plan = client.run(
        "EXPLAIN SELECT requestId FROM clp.default.http_logs"
        " WHERE timestamp < TIMESTAMP '2025-04-30 08:50:00'"
    )
    assert len(plan) == 1
    assert "kqlQuery=Optional[timestamp < timestamp(" in plan[0][0]
