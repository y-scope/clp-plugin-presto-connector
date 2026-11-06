"""Case-insensitive string matching, at each tier that can configure it."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from clp_presto_integration_tests.client import PrestoClient

pytestmark = pytest.mark.pushdown

# The fixtures record `method` in upper case, so a lower-case literal matches only when
# case-insensitive matching is on.
_LOWER_CASE_POST_200 = "WHERE method = 'post' AND status = 200"

# The one record that satisfies the predicate when matching ignores case.
_POST_200_REQUEST_ID = [["req-106"]]

_TABLES = [
    pytest.param("http_logs", marks=pytest.mark.archive, id="archive"),
    pytest.param("http_logs_ir", marks=pytest.mark.ir, id="ir"),
]

# Sent as `X-Presto-Session`, so the name is catalog-qualified.
_CASE_INSENSITIVE_SESSION = {"clp.case_insensitive": "true"}


@pytest.mark.parametrize("table", _TABLES)
def test_matching_is_case_sensitive_by_default(client: PrestoClient, table: str) -> None:
    """A lower-case literal matches nothing until a tier turns case-insensitivity on."""
    rows = client.run(f"SELECT requestId FROM clp.default.{table} {_LOWER_CASE_POST_200}")
    assert rows == []


@pytest.mark.parametrize("table", _TABLES)
def test_session_property_makes_matching_case_insensitive(client: PrestoClient, table: str) -> None:
    """The session property reaches the native worker and changes how values are compared."""
    rows = client.run(
        f"SELECT requestId FROM clp.default.{table} {_LOWER_CASE_POST_200}",
        session_properties=_CASE_INSENSITIVE_SESSION,
    )
    assert rows == _POST_200_REQUEST_ID


@pytest.mark.parametrize("table", _TABLES)
def test_catalog_config_makes_matching_case_insensitive(client: PrestoClient, table: str) -> None:
    """`clp.case-insensitive=true` in the catalog properties is the default for its sessions."""
    rows = client.run(f"SELECT requestId FROM clp_ci.default.{table} {_LOWER_CASE_POST_200}")
    assert rows == _POST_200_REQUEST_ID
