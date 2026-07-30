"""Push pre-built Benchling payloads to the tenant — the network side.
Companion to genscript_parse.py; low-level helpers come from benchling_io.py.
"""

import sys
import time

from benchling_sdk.benchling import Benchling
from benchling_sdk.models import AsyncTaskStatus

from benchling_io import chunked, log, wait_for_task


def resolve_dropdown(benchling: Benchling, dropdown_name: str, option_name: str) -> str:
    for page in benchling.dropdowns.list():
        for s in page:
            if s.name != dropdown_name:
                continue
            full = benchling.dropdowns.get_by_id(s.id)
            for opt in full.options:
                if opt.name == option_name:
                    return opt.id
            sys.exit(f"[BENCHLING_PUSH] ERROR: option {option_name!r} not found "
                     f"in dropdown {dropdown_name!r}")
    sys.exit(f"[BENCHLING_PUSH] ERROR: dropdown {dropdown_name!r} not found")


def create_boxes(benchling: Benchling, box_payloads: list) -> dict:
    """Create each pre-built [(box_key, BoxCreate)] -> {box_key: box_id}."""
    out: dict = {}
    for key, payload in box_payloads:
        log("BENCHLING_PUSH", f"creating box {payload.name!r} ...")
        box = benchling.boxes.create(payload)
        out[key] = box.id
    return out


def run_bulk(benchling: Benchling, items: list, label: str, chunk_size: int,
             submit, extract=None) -> list | None:
    """Chunk + submit + wait, raising on any non-SUCCEEDED chunk. With `extract`,
    pull result rows from each task.response (length-checked) and return them;
    without it (transfers, which return no rows) return None."""
    results: list = []
    done, total = 0, len(items)
    for chunk in chunked(items, chunk_size):
        log("BENCHLING_PUSH", f"{label}: submitting {done + 1}..{done + len(chunk)} of {total} ...")
        t0 = time.time()
        task = wait_for_task(benchling, submit(chunk).task_id)
        log("BENCHLING_PUSH", f"{label}: chunk done in {time.time() - t0:.1f}s")
        if task.status != AsyncTaskStatus.SUCCEEDED:
            errors = getattr(task, "errors", None)
            raise RuntimeError(f"{label} chunk failed (status={task.status}): "
                               f"{errors or task.message}")
        if extract is not None:
            rows = extract(getattr(task, "response", {}) or {})
            if len(rows) != len(chunk):
                raise RuntimeError(f"{label} returned {len(rows)} rows "
                                   f"for a chunk of {len(chunk)}")
            results.extend(rows)
        done += len(chunk)
    return results if extract is not None else None


def entity_field(e, *names):
    """First present field (e.g. "id", "barcode") of a raw entity (dict or object)."""
    if isinstance(e, dict):
        return next((e[n] for n in names if n in e), "")
    return next((getattr(e, n) for n in names if getattr(e, n, None) is not None), "")
