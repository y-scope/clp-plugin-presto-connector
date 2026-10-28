"""Tests table and column discovery from a directory of archives, with no metadata database."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from clp_presto_integration_tests.client import PrestoClient

pytestmark = pytest.mark.schema


def test_tables_are_the_fixture_directories(
    client: PrestoClient, fixture_tables: list[str]
) -> None:
    """
    Each directory under the archive directory has a corresponding table that is named
    after the directory name.
    """
    rows = client.run(
        "SELECT table_name FROM clp.information_schema.tables"
        " WHERE table_schema = 'default' ORDER BY 1"
    )
    assert [row[0] for row in rows] == fixture_tables


def test_schema_file_yields_typed_columns(client: PrestoClient) -> None:
    """A table that has a schema.json exposes real typed columns, as a MySQL-backed table would."""
    rows = client.run(
        "SELECT column_name, data_type FROM clp.information_schema.columns"
        " WHERE table_schema = 'default' AND table_name = 'http_logs' ORDER BY 1"
    )
    assert [(row[0], row[1]) for row in rows] == [
        ("method", "varchar"),
        ("path", "varchar"),
        ("requestId", "varchar"),
        ("responseTimeMs", "bigint"),
        ("status", "bigint"),
        ("timestamp", "timestamp"),
        ("userId", "varchar"),
    ]


def test_table_without_schema_file_falls_back_to_json_string(
    client: PrestoClient,
) -> None:
    """A table that has no schema.json exposes only __json_string, which the CLP_GET_* UDFs read."""
    rows = client.run(
        "SELECT column_name FROM clp.information_schema.columns"
        " WHERE table_schema = 'default' AND table_name = 'legacy_archive'"
    )
    assert [row[0] for row in rows] == ["__json_string"]


def test_polymorphic_field_splits_into_typed_columns(client: PrestoClient) -> None:
    """
    CLP stores a field under every type that it was written with, and each becomes its own column.

    `ClpSchemaTree.resolvePolymorphicConflicts` adds the type as a suffix, so a `timestamp` field
    that was written as an integer, as a float, and as a timestamp surfaces as three columns
    rather than as one.
    """
    rows = client.run(
        "SELECT column_name FROM clp.information_schema.columns"
        " WHERE table_schema = 'default' AND table_name = 'timestamps' ORDER BY 1"
    )
    assert [row[0] for row in rows] == [
        "timestamp_bigint",
        "timestamp_double",
        "timestamp_timestamp",
    ]
