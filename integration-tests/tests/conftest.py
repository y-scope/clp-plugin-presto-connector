"""Shared fixtures: the cluster, and a client pointed at it."""

from __future__ import annotations

import os
from collections.abc import Iterator
from pathlib import Path

import pytest

from clp_presto_integration_tests.client import PrestoClient
from clp_presto_integration_tests.cluster import compose_run, wait_until_ready

_COORDINATOR_HOST = os.environ.get("CLP_INTEGRATION_TEST_COORDINATOR_HOST", "localhost")
_COORDINATOR_PORT = int(os.environ.get("CLP_INTEGRATION_TEST_COORDINATOR_PORT", "18080"))

# The tree docker-compose.yaml mounts, resolved the same way it resolves it.
_FIXTURE_DIR = Path(
    os.environ.get(
        "CLP_INTEGRATION_TEST_FIXTURE_DIR",
        Path(__file__).resolve().parents[1] / "fixtures",
    )
)


def pytest_addoption(parser: pytest.Parser) -> None:
    """Adds options for reusing or keeping the cluster, which speed up local iteration."""
    parser.addoption(
        "--keep-cluster",
        action="store_true",
        help="Leave the cluster running after the session, for debugging.",
    )
    parser.addoption(
        "--use-running-cluster",
        action="store_true",
        help="Run against an already-running cluster instead of starting one.",
    )


@pytest.fixture(scope="session")
def client(request: pytest.FixtureRequest) -> Iterator[PrestoClient]:
    """Brings the cluster up for the session and yields a client for it."""
    presto = PrestoClient(_COORDINATOR_HOST, _COORDINATOR_PORT)

    if request.config.getoption("--use-running-cluster"):
        wait_until_ready(presto)
        yield presto
        return

    compose_run("up", "-d")
    try:
        wait_until_ready(presto)
        yield presto
    finally:
        if not request.config.getoption("--keep-cluster"):
            compose_run("down", "--volumes", check=False)


@pytest.fixture(scope="session")
def fixture_tables() -> list[str]:
    """The table names the connector should report: one per directory in the fixture tree."""
    tables = sorted(entry.name for entry in _FIXTURE_DIR.iterdir() if entry.is_dir())
    if not tables:
        msg = f"no fixture directories under {_FIXTURE_DIR}"
        raise AssertionError(msg)
    return tables
