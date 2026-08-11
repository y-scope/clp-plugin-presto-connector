"""Waits for the Presto cluster that the tests run against."""

from __future__ import annotations

import time
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from clp_presto_integration_tests.client import PrestoClient

_READY_TIMEOUT_SECONDS = 240
_READY_POLL_SECONDS = 5


def wait_until_ready(client: PrestoClient) -> None:
    """
    Blocks until the cluster can run queries, and raises a `TimeoutError` if it never can.

    The cluster is started by `task integration-tests:up`, so a timeout means it is unreachable or
    has no worker rather than that it was never started. `docker compose logs` shows which.
    """
    deadline = time.monotonic() + _READY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if client.is_ready():
            return
        time.sleep(_READY_POLL_SECONDS)
    msg = f"cluster did not become ready in {_READY_TIMEOUT_SECONDS}s"
    raise TimeoutError(msg)
