"""Shared Benchling I/O helpers used by the GenScript uploader and the cleanup
tool: client connect, resilient async-task polling, and chunking.
"""
import os
import sys
import time

import httpx
from benchling_sdk.auth.api_key_auth import ApiKeyAuth
from benchling_sdk.benchling import Benchling
from benchling_sdk.models import AsyncTaskStatus

# Transient network errors worth retrying (httpx timeouts + dropped connections).
NET_ERRS = (
    httpx.ReadTimeout, httpx.ConnectTimeout, httpx.WriteTimeout,
    httpx.PoolTimeout, httpx.RemoteProtocolError,
)


def connect(env: str) -> Benchling:
    """Benchling client for `env` ('test'/'prod'), built from .env credentials.

    The default 5s httpx read timeout is too short for Benchling task polls under
    load, so bump it to 120s; the SDK's built-in 429/5xx retry still applies.
    """
    env_upper = env.upper()
    url = os.environ.get(f"BENCHLING_{env_upper}_TENANT_URL")
    key = os.environ.get(f"BENCHLING_{env_upper}_API_KEY")
    if not (url and key):
        sys.exit(f"ERROR: set BENCHLING_{env_upper}_TENANT_URL and "
                 f"BENCHLING_{env_upper}_API_KEY in .env")
    client = httpx.Client(timeout=httpx.Timeout(120.0, connect=10.0))
    return Benchling(url=url, auth_method=ApiKeyAuth(key), httpx_client=client)


def wait_for_task(benchling: Benchling, task_id: str,
                  max_wait_seconds: int = 1800, poll_interval: float = 2.0):
    """Poll until an async task leaves RUNNING; transient network errors are retried."""
    start = time.time()
    while time.time() - start < max_wait_seconds:
        try:
            task = benchling.tasks.get_by_id(task_id)
            if task.status != AsyncTaskStatus.RUNNING:
                return task
        except NET_ERRS as e:
            print(f"    (task poll retry: {type(e).__name__})", flush=True)
        time.sleep(poll_interval)
    raise TimeoutError(f"task {task_id} did not complete in {max_wait_seconds}s")


def chunked(seq, n):
    """Yield successive n-sized chunks of `seq`."""
    for i in range(0, len(seq), n):
        yield seq[i : i + n]


def log(label, msg):
    """Print a timestamped, category-tagged line: HH:MM:SS [label] msg."""
    print(f"{time.strftime('%H:%M:%S')} [{label}] {msg}")
