"""'Upload complete' marker: a per-order child folder under a shared parent folder.

The order uploader creates the marker as its final step, after every phase has succeeded, so a
half-finished or failed push never leaves one behind. Status treats "marker present" as the
definitive fully-uploaded signal — no entity counting, which can't see a failure in the final
transfer phase anyway. Cleanup archives the marker.

The parent is resolved by name rather than configured, so every install lands on the same folder
or fails outright. A per-machine folder id is what let two people disagree about the same order.
"""

from benchling_sdk.benchling import Benchling
from benchling_sdk.models import FolderCreate, FoldersArchiveReason

MARKER_FOLDER_NAME = "GenScript Upload Markers"

_resolved: dict[str, str] = {}


def marker_parent_id(benchling: Benchling, env: str) -> str:
    """Id of the marker parent. Raises unless exactly one active folder carries the name."""
    if env in _resolved:
        return _resolved[env]
    matches = [f for page in benchling.folders.list(name=MARKER_FOLDER_NAME) for f in page
               if getattr(f, "archive_record", None) is None and f.name == MARKER_FOLDER_NAME]
    if not matches:
        raise RuntimeError(f"marker folder {MARKER_FOLDER_NAME!r} not found on the {env} tenant — "
                           f"create it in Benchling")
    if len(matches) > 1:
        raise RuntimeError(f"{len(matches)} folders named {MARKER_FOLDER_NAME!r} on the {env} "
                           f"tenant ({', '.join(f.id for f in matches)}) — leave exactly one")
    _resolved[env] = matches[0].id
    return _resolved[env]


def _marker_folders(benchling: Benchling, parent_id: str, prefix: str) -> list:
    """Active child folders of the parent whose name is exactly the order prefix."""
    return [f for page in benchling.folders.list(parent_folder_id=parent_id, name=prefix)
            for f in page
            if getattr(f, "archive_record", None) is None and f.name == prefix]


def has_marker(benchling: Benchling, prefix: str, env: str) -> bool:
    """Whether this order's marker exists."""
    return bool(_marker_folders(benchling, marker_parent_id(benchling, env), prefix))


def list_markers(benchling: Benchling, env: str) -> set[str]:
    """Every completed order prefix in one listing — a sync's whole batch, without a lookup per
    order."""
    parent = marker_parent_id(benchling, env)
    return {f.name for page in benchling.folders.list(parent_folder_id=parent) for f in page
            if getattr(f, "archive_record", None) is None and f.name}


def write_marker(benchling: Benchling, prefix: str, env: str) -> str:
    """Create the order's marker folder (idempotent); return its id."""
    parent = marker_parent_id(benchling, env)
    existing = _marker_folders(benchling, parent, prefix)
    if existing:
        return existing[0].id
    return benchling.folders.create(FolderCreate(name=prefix, parent_folder_id=parent)).id


def archive_marker(benchling: Benchling, prefix: str, env: str) -> int:
    """Archive the order's marker folder(s); return how many were archived."""
    ids = [f.id for f in _marker_folders(benchling, marker_parent_id(benchling, env), prefix)]
    if ids:
        benchling.folders.archive(ids, FoldersArchiveReason.MADE_IN_ERROR)
    return len(ids)
