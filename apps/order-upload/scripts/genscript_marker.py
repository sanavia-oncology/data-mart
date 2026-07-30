"""'Upload complete' marker: a per-order child folder under a configured parent folder.

The order uploader creates the marker as its final step, after every phase has succeeded, so a
half-finished or failed push never leaves one behind. Status treats "marker present" as the
definitive fully-uploaded signal — no entity counting, which can't see a failure in the final
transfer phase anyway. Cleanup archives the marker.

Config: GENSCRIPT_<ENV>_MARKER_FOLDER_ID = the parent folder id (lib_...). If unset, markers are
disabled and callers fall back to their own heuristics (has_marker returns None).
"""

import os

from benchling_sdk.benchling import Benchling
from benchling_sdk.models import FolderCreate, FoldersArchiveReason


def marker_parent_id(env: str) -> str | None:
    return os.environ.get(f"GENSCRIPT_{env.upper()}_MARKER_FOLDER_ID") or None


def _marker_folders(benchling: Benchling, parent_id: str, prefix: str) -> list:
    """Active child folders of the parent whose name is exactly the order prefix."""
    return [f for page in benchling.folders.list(parent_folder_id=parent_id, name=prefix)
            for f in page
            if getattr(f, "archive_record", None) is None and f.name == prefix]


def has_marker(benchling: Benchling, prefix: str, env: str) -> bool | None:
    """True/False when markers are configured for this env, None when they aren't."""
    parent = marker_parent_id(env)
    if parent is None:
        return None
    return bool(_marker_folders(benchling, parent, prefix))


def list_markers(benchling: Benchling, env: str) -> set[str] | None:
    """Every completed order prefix in one listing — a sync's whole batch, without a lookup per
    order. None when markers aren't configured."""
    parent = marker_parent_id(env)
    if parent is None:
        return None
    return {f.name for page in benchling.folders.list(parent_folder_id=parent) for f in page
            if getattr(f, "archive_record", None) is None and f.name}


def write_marker(benchling: Benchling, prefix: str, env: str) -> str | None:
    """Create the order's marker folder (idempotent); return its id, or None if unconfigured."""
    parent = marker_parent_id(env)
    if parent is None:
        return None
    existing = _marker_folders(benchling, parent, prefix)
    if existing:
        return existing[0].id
    return benchling.folders.create(FolderCreate(name=prefix, parent_folder_id=parent)).id


def archive_marker(benchling: Benchling, prefix: str, env: str) -> int:
    """Archive the order's marker folder(s); return how many were archived."""
    parent = marker_parent_id(env)
    if parent is None:
        return 0
    ids = [f.id for f in _marker_folders(benchling, parent, prefix)]
    if ids:
        benchling.folders.archive(ids, FoldersArchiveReason.MADE_IN_ERROR)
    return len(ids)
