"""Lifecycle for the Presto cluster the tests run against."""

from __future__ import annotations

import subprocess
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from clp_presto_integration_tests.client import PrestoClient

_PROJECT_DIR = Path(__file__).resolve().parents[2]
_READY_TIMEOUT_SECONDS = 240
_READY_POLL_SECONDS = 5


def compose_run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Runs `docker compose`, raising with its stderr on failure rather than just an exit code."""
    result = subprocess.run(
        ["docker", "compose", *args],
        cwd=_PROJECT_DIR,
        check=False,
        capture_output=True,
        text=True,
    )
    if check and 0 != result.returncode:
        msg = f"`docker compose {' '.join(args)}` exited {result.returncode}\n{result.stderr}"
        raise RuntimeError(msg)
    return result


def wait_until_ready(client: PrestoClient) -> None:
    """Blocks until the cluster can run queries, dumping container logs if it never does."""
    deadline = time.monotonic() + _READY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if client.is_ready():
            return
        time.sleep(_READY_POLL_SECONDS)
    logs = compose_run("logs", "--tail", "40", check=False).stdout
    msg = f"cluster did not become ready in {_READY_TIMEOUT_SECONDS}s\n{logs}"
    raise TimeoutError(msg)
