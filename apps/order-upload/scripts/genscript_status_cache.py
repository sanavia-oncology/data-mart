"""Local mirror of each order's upload state, so the app paints statuses without a Benchling round
trip. Benchling stays the source of truth: genscript_status.py rewrites whatever it checked.

Path: $GENSCRIPT_LOGS_DIR/status-<env>.json, else <cwd>/logs/ — the app sets the var so a dev
worktree checkout still writes the logs/ the app reads.
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path

VERSION = 1


def cache_path(env: str) -> Path:
    base = os.environ.get("GENSCRIPT_LOGS_DIR") or Path.cwd() / "logs"
    return Path(base) / f"status-{env}.json"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def entry(state: str) -> dict:
    return {"state": state, "uploaded": state == "complete", "checked_at": _now()}


def read_states(env: str) -> dict[str, dict]:
    """{prefix: entry}, or {} when the cache is missing or unreadable."""
    try:
        doc = json.loads(cache_path(env).read_text())
    except (OSError, ValueError):
        return {}
    orders = doc.get("orders") if isinstance(doc, dict) else None
    return orders if isinstance(orders, dict) else {}


def write_states(env: str, states: dict[str, dict]) -> Path | None:
    """Merge `states` in, but only if a state actually changed — a check that agrees with the
    mirror leaves the file untouched. Replaced atomically so a concurrent reader never sees half a
    file; None on failure, which only costs the app its head start."""
    if not states:
        return None
    path = cache_path(env)
    current = read_states(env)
    if all(current.get(p, {}).get("state") == s.get("state") for p, s in states.items()):
        return path
    doc = {"version": VERSION, "env": env, "synced_at": _now(),
           "orders": {**current, **states}}
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(doc, indent=1, sort_keys=True))
        os.replace(tmp, path)
        return path
    except OSError:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        return None


def set_state(env: str, prefix: str, state: str) -> Path | None:
    """Stamp one order — only once its Benchling marker write/archive has succeeded."""
    return write_states(env, {prefix: entry(state)})
