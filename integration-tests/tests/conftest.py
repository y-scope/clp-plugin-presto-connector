"""Fixtures shared by every test: the cluster itself, and a client that talks to it."""

from __future__ import annotations

import os
from collections.abc import Iterator
from pathlib import Path

import pytest

from clp_presto_integration_tests.client import PrestoClient
from clp_presto_integration_tests.cluster import compose_run, wait_until_ready

_COORDINATOR_HOST = os.environ.get("CLP_INTEGRATION_TEST_COORDINATOR_HOST", "localhost")
_COORDINATOR_PORT = int(os.environ.get("CLP_INTEGRATION_TEST_COORDINATOR_PORT", "18080"))

# The directory that docker-compose.yaml mounts into the cluster. This resolves it the same
# way the compose file does, so that both agree on which fixtures the cluster is serving.
_FIXTURE_DIR = Path(
    os.environ.get(
        "CLP_INTEGRATION_TEST_FIXTURE_DIR",
        Path(__file__).resolve().parents[1] / "fixtures",
    )
)


def pytest_addoption(parser: pytest.Parser) -> None:
    """Adds the options that let a developer reuse or keep the cluster between runs."""
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
    """Brings the cluster up for the whole session, and yields a client that is connected to it."""
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
    """The table names that the connector should report: one for each directory of fixtures."""
    tables = sorted(entry.name for entry in _FIXTURE_DIR.iterdir() if entry.is_dir())
    if not tables:
        msg = f"no fixture directories under {_FIXTURE_DIR}"
        raise AssertionError(msg)
    return tables
