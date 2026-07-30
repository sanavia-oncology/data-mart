"""Undo a GenScript order push: rediscover every entity for an --order-id from the
tenant, then archive containers + boxes and rename + archive lots + sequences.

Usage: python scripts/dev-tools/cleanup_run.py --order-id U0000AAAA0 --env test [--yes]
"""

import argparse
import sys
import time
from pathlib import Path

# cleanup_run.py lives in scripts/dev-tools/; put scripts/ on the path so the shared
# modules one level up (benchling_io, genscript_parse) import cleanly.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from dotenv import load_dotenv

from benchling_sdk.benchling import Benchling
from benchling_sdk.errors import BenchlingError
from benchling_sdk.models import (
    AaSequenceBulkUpdate,
    AaSequenceUpdate,
    AsyncTaskStatus,
    BoxesArchiveReason,
    ContainersArchiveReason,
    CustomEntityBulkUpdate,
    CustomEntityUpdate,
    EntityArchiveReason,
)

from benchling_io import NET_ERRS, chunked, connect, wait_for_task
from genscript_marker import archive_marker
from genscript_parse import SCHEMAS  # single source of truth for schema ids
from genscript_status_cache import set_state

DELETED_PREFIX = "_GENSCRIPT_DELETED_"

# Worth catching: SDK errors + transient httpx timeouts (NET_ERRS). Anything
# else (auth, programming errors) should still propagate.
_CATCH = (BenchlingError, *NET_ERRS)

ARCHIVE_CHUNK = 50  # archive in chunks so a single timeout doesn't lose the whole batch
BULK_CHUNK = 100    # Benchling caps bulk_update at 100 per request


def retry(fn, label: str, max_tries: int = 4):
    """Retry on transient network errors with exponential backoff."""
    for attempt in range(max_tries):
        try:
            return fn()
        except NET_ERRS as e:
            if attempt == max_tries - 1:
                raise
            print(f"  {label} retry {attempt + 1}/{max_tries}: {type(e).__name__}", flush=True)
            time.sleep(2 ** attempt)


# =============================================================================
# Rediscover ids straight from the tenant, by order id
# =============================================================================

def _iter_items(page_iter):
    """Flatten a paginated list() result into individual items."""
    for page in page_iter:
        for item in page:
            yield item


def _active(item) -> bool:
    """True if not already archived. list() excludes archived by default; this is
    a belt-and-suspenders guard so a re-run never tries to re-archive."""
    return getattr(item, "archive_record", None) is None


def _list_all(list_fn, label: str) -> list:
    """Materialize a paginated list(), retrying transient network errors."""
    return retry(lambda: list(_iter_items(list_fn())), label)


def _seq_link_ids(lot) -> list[str]:
    """The Sequence1..4 entity ids linked on a GenScript Lot — the inverse of how
    the uploader stamped them."""
    ids: list[str] = []
    fields = lot.fields
    if fields is None:
        return ids
    for n in (1, 2, 3, 4):
        f = fields.get(f"Sequence{n}")
        if f is None:
            continue
        v = f.value
        if isinstance(v, list):          # multi-link, just in case
            ids.extend(x for x in v if x)
        elif v:
            ids.append(v)
    return ids


def discover_ids(benchling: Benchling, order_id: str
                 ) -> tuple[list[str], list[str], list[str], list[str]]:
    """Rediscover (seq_ids, lot_ids, container_ids, box_ids) for an order-id prefix.
    Lots/boxes/containers match the prefix in their names; sequences via their lots'
    links + an "Order ID"-field scan (catches orphans from a failed run)."""
    prefix = order_id.strip()

    print(f"  Lots: schema {SCHEMAS['lot']}, name startswith {prefix!r} ...", flush=True)
    lot_ids: dict[str, None] = {}
    seq_ids: dict[str, None] = {}
    for lot in _list_all(lambda: benchling.custom_entities.list(
            schema_id=SCHEMAS["lot"], name_includes=prefix), "lots.list"):
        if not (_active(lot) and (lot.name or "").startswith(prefix)):
            continue
        lot_ids.setdefault(lot.id, None)
        for sid in _seq_link_ids(lot):
            seq_ids.setdefault(sid, None)

    # Orphaned sequences (no Lot links them): match the "Order ID" field, "<prefix>-<n>".
    print(f"  Sequences: scanning schema for Order ID {prefix!r} ...", flush=True)
    for seq in _list_all(lambda: benchling.aa_sequences.list(
            schema_id=SCHEMAS["sequence"], page_size=100), "sequences.list"):
        if not _active(seq):
            continue
        of = seq.fields.get("Order ID") if seq.fields else None
        if (getattr(of, "value", None) or "").split("-", 1)[0] == prefix:
            seq_ids.setdefault(seq.id, None)

    print(f"  Boxes: name startswith {prefix!r} ...", flush=True)
    box_ids: dict[str, None] = {}
    for box in _list_all(lambda: benchling.boxes.list(name_includes=prefix), "boxes.list"):
        if _active(box) and (box.name or "").startswith(prefix):
            box_ids.setdefault(box.id, None)

    print(f"  Containers: name startswith {prefix!r} ...", flush=True)
    container_ids: dict[str, None] = {}
    for c in _list_all(lambda: benchling.containers.list(
            schema_id=SCHEMAS["container"], name_includes=prefix), "containers.list"):
        if _active(c) and (c.name or "").startswith(prefix):
            container_ids.setdefault(c.id, None)

    print(f"  discovered: {len(container_ids)} containers, {len(box_ids)} boxes, "
          f"{len(lot_ids)} lots, {len(seq_ids)} sequences")
    return (list(seq_ids), list(lot_ids), list(container_ids), list(box_ids))


def safe_unarchive(unarchive_fn, ids: list[str]) -> None:
    """Best-effort unarchive — many entities will already be active; that's fine."""
    if not ids:
        return
    try:
        unarchive_fn(ids)
    except _CATCH as e:
        print(f"  (unarchive note: {e})")


def archive_only(benchling: Benchling, ids: list[str], kind: str) -> int:
    """Archive storage objects (containers, boxes). No rename needed — they aren't
    registry entities, so their names aren't reserved."""
    if not ids:
        return 0
    if kind == "container":
        archive_one = lambda b: benchling.containers.archive(
            b, reason=ContainersArchiveReason.MADE_IN_ERROR,
            should_remove_barcodes=True)
        unarchive_fn = benchling.containers.unarchive
    elif kind == "box":
        archive_one = lambda b: benchling.boxes.archive(
            b, reason=BoxesArchiveReason.MADE_IN_ERROR,
            should_remove_barcodes=True)
        unarchive_fn = benchling.boxes.unarchive
    else:
        raise ValueError(f"unknown kind: {kind}")
    safe_unarchive(unarchive_fn, ids)
    for batch in chunked(ids, ARCHIVE_CHUNK):
        print(f"  archiving {len(batch)} {kind}s ...", flush=True)
        retry(lambda b=batch: archive_one(b), f"{kind}.archive")
    return len(ids)


def rename_and_archive(benchling: Benchling, ids: list[str], kind: str,
                        ts: str) -> int:
    """For registry entities: rename to a placeholder (frees the original name),
    then archive. Renames go through bulk_update (one async task per 100), with a
    per-entity fallback if a bulk chunk fails so names still get freed."""
    if not ids:
        return 0

    if kind == "aa_sequence":
        bulk_update = benchling.aa_sequences.bulk_update
        make_bulk = lambda eid, nm: AaSequenceBulkUpdate(id=eid, name=nm, aliases=[])
        update_one = lambda eid, nm: benchling.aa_sequences.update(
            eid, AaSequenceUpdate(name=nm, aliases=[]))
        archive_batch = lambda batch: benchling.aa_sequences.archive(
            batch, reason=EntityArchiveReason.MADE_IN_ERROR)
        safe_unarchive(benchling.aa_sequences.unarchive, ids)
    elif kind == "custom_entity":
        bulk_update = benchling.custom_entities.bulk_update
        make_bulk = lambda eid, nm: CustomEntityBulkUpdate(id=eid, name=nm, aliases=[])
        update_one = lambda eid, nm: benchling.custom_entities.update(
            eid, CustomEntityUpdate(name=nm, aliases=[]))
        archive_batch = lambda batch: benchling.custom_entities.archive(
            batch, reason=EntityArchiveReason.MADE_IN_ERROR)
        safe_unarchive(benchling.custom_entities.unarchive, ids)
    else:
        raise ValueError(f"unknown kind: {kind}")

    def placeholder(i: int) -> str:
        return f"{DELETED_PREFIX}{ts}_{kind}_{i:04d}"

    done = 0
    total = len(ids)
    for start in range(0, total, BULK_CHUNK):
        chunk = ids[start : start + BULK_CHUNK]
        updates = [make_bulk(eid, placeholder(start + j)) for j, eid in enumerate(chunk)]
        print(f"  renaming {start + 1}..{start + len(chunk)} of {total} {kind}s ...", flush=True)
        try:
            helper = retry(lambda u=updates: bulk_update(u), f"{kind}.bulk_update")
            task = wait_for_task(benchling, helper.task_id)
            if task.status == AsyncTaskStatus.SUCCEEDED:
                done += len(chunk)
                continue
            print(f"  WARN: bulk rename chunk failed (status={task.status}); "
                  f"falling back to per-entity", flush=True)
        except _CATCH as e:
            print(f"  WARN: bulk rename chunk errored ({e}); falling back to per-entity",
                  flush=True)
        # Fallback: rename this chunk one at a time (re-renaming any that already
        # succeeded in a partial bulk is harmless — same placeholder).
        for j, eid in enumerate(chunk):
            try:
                retry(lambda eid=eid, nm=placeholder(start + j): update_one(eid, nm),
                      f"{kind}.update[{start + j}]", max_tries=3)
                done += 1
            except _CATCH as e:
                print(f"  WARN: rename failed for {eid}: {e}", flush=True)

    if done:
        for batch in chunked(ids, ARCHIVE_CHUNK):
            print(f"  archiving {len(batch)} {kind}s ...", flush=True)
            retry(lambda b=batch: archive_batch(b), f"{kind}.archive")
    return done


def parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Archive + free names from a previous push.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--order-id", required=True,
                   help="Order-id prefix to clean up (e.g. U0000AAAA0). Every entity "
                        "for the order is rediscovered straight from the tenant.")
    p.add_argument("--env", choices=["test", "prod"], default="test",
                   help="Tenant to clean up in.")
    p.add_argument("--yes", action="store_true",
                   help="Skip the confirmation prompt.")
    return p.parse_args(argv)


def main() -> int:
    load_dotenv()
    args = parse_args()

    benchling = connect(args.env)
    print(f"Connected to {args.env} tenant")
    print(f"Discovering entities for order {args.order_id!r} from the tenant ...")
    seq_ids, lot_ids, container_ids, box_ids = discover_ids(benchling, args.order_id)
    source = f"order {args.order_id!r} (tenant)"
    prefix = args.order_id.strip().split("-", 1)[0]

    total = len(seq_ids) + len(lot_ids) + len(container_ids) + len(box_ids)
    if total == 0:
        n_marker = archive_marker(benchling, prefix, args.env)   # drop a stray completion marker too
        set_state(args.env, prefix, "none")
        print(f"Nothing to clean up for {source}."
              + (f" Archived {n_marker} completion marker folder." if n_marker else ""))
        return 0

    print(f"Cleanup plan from {source}:")
    print(f"  Containers:          {len(container_ids)}")
    print(f"  Boxes:               {len(box_ids)}")
    print(f"  GenScript Lots:      {len(lot_ids)}")
    print(f"  GenScript Sequences: {len(seq_ids)}")

    if not args.yes:
        confirm = input(f"\nArchive these {total} items in {args.env}? [y/N] ").strip().lower()
        if confirm not in ("y", "yes"):
            print("Aborted.")
            return 1

    ts = time.strftime("%Y%m%d-%H%M%S")

    # Containers first — releases the box slots.
    n_con = archive_only(benchling, container_ids, "container")
    # Boxes next — now empty.
    n_box = archive_only(benchling, box_ids, "box")
    # Lots — registry name needs release.
    n_lot = rename_and_archive(benchling, lot_ids, "custom_entity", ts)
    # Sequences last.
    n_seq = rename_and_archive(benchling, seq_ids, "aa_sequence", ts)
    # Completion marker — remove it so the order reads "not uploaded" again.
    n_marker = archive_marker(benchling, prefix, args.env)
    if n_marker:
        print(f"  archived {n_marker} completion marker folder")

    failed = (len(container_ids) - n_con) + (len(box_ids) - n_box) \
             + (len(lot_ids) - n_lot) + (len(seq_ids) - n_seq)
    set_state(args.env, prefix, "partial" if failed else "none")   # leftovers, marker gone = partial
    print(f"\n=== archived: {n_con} containers, {n_box} boxes, "
          f"{n_lot} lots, {n_seq} sequences, {n_marker} marker | failed: {failed} ===")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
