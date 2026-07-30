"""Push a GenScript antibody order CSV to Benchling (test tenant only). Thin
orchestrator: genscript_parse.py builds the payloads, genscript_upload.py pushes.

Run: python genscript_order_uploader.py --csv merged.csv --location loc_xxx
"""

import argparse
import sys
from pathlib import Path

from dotenv import load_dotenv

from benchling_io import connect, log
from genscript_marker import write_marker
from genscript_parse import (
    CONTAINER_TYPE,
    build_box_payloads,
    build_container_payloads,
    build_lot_payloads,
    build_sequence_payloads,
    build_transfer_requests,
    build_tubes,
    flatten,
    read_csv,
    seq_offsets,
    validate_tubes,
)
from genscript_status_cache import set_state
from genscript_upload import create_boxes, entity_field, resolve_dropdown, run_bulk

BATCH_SIZE_DEFAULT = 100  # Benchling caps bulk_create / transfer at 100 per request.


def _rows(*keys):
    """Extractor for run_bulk: the first non-empty list among task.response[keys]."""
    return lambda r: next((r.get(k) for k in keys if r.get(k)), [])


def upload(benchling, df, tubes_by_row: list[list[dict]], registry_id: str,
           location_id: str, container_type_id: str, chunk_size: int) -> int:
    """Build then push each of the 5 phases; `stage` tags which one failed on error.
    Recover a failed run with `scripts/dev-tools/cleanup_run.py --order-id`."""
    flat = flatten(tubes_by_row)
    n_rows, n_tubes = len(df), len(flat)
    stage = "LOCAL_BUILD"

    try:
        log(stage := "LOCAL_BUILD", f"building sequence payloads for {n_rows} row(s) ...")
        seq_payloads, counts = build_sequence_payloads(df, registry_id)
        offsets = seq_offsets(counts)
        seqs_per_row = ", ".join(f"{c}×{counts.count(c)}" for c in sorted(set(counts)))
        log(stage := "BENCHLING_PUSH", f"creating {len(seq_payloads)} GenScript Sequence "
            f"entities ({seqs_per_row} per row, chunks of {chunk_size}) ...")
        seq_entries = run_bulk(benchling, seq_payloads, "sequences", chunk_size,
                               submit=benchling.aa_sequences.bulk_create,
                               extract=_rows("aaSequences", "aa_sequences"))
        sequence_ids = [entity_field(e, "id") for e in seq_entries]

        log(stage := "LOCAL_BUILD", f"building {n_rows} lot payload(s) ...")
        lot_payloads = build_lot_payloads(df, registry_id, sequence_ids, offsets, tubes_by_row)
        log(stage := "BENCHLING_PUSH", f"creating {n_rows} GenScript Lot entities "
            f"(chunks of {chunk_size}) ...")
        lot_entries = run_bulk(benchling, lot_payloads, "lots", chunk_size,
                               submit=benchling.custom_entities.bulk_create,
                               extract=_rows("customEntities", "custom_entities"))
        lot_ids = [entity_field(e, "id") for e in lot_entries]

        order_prefix = str(df["Order ID"].iloc[0]).split("-", 1)[0]
        log(stage := "LOCAL_BUILD", "building box payloads ...")
        box_payloads = build_box_payloads(tubes_by_row, order_prefix, location_id)
        log(stage := "BENCHLING_PUSH", f"creating {len(box_payloads)} unique box(es) ...")
        box_id_by_key = create_boxes(benchling, box_payloads)

        log(stage := "LOCAL_BUILD", f"building {n_tubes} container payload(s) ...")
        container_payloads = build_container_payloads(flat, df, box_id_by_key, container_type_id)
        log(stage := "BENCHLING_PUSH", f"creating {n_tubes} containers (chunks of {chunk_size}) ...")
        container_entries = run_bulk(benchling, container_payloads, "containers", chunk_size,
                                     submit=benchling.containers.bulk_create,
                                     extract=_rows("containers"))
        container_ids = [entity_field(e, "id") for e in container_entries]

        log(stage := "LOCAL_BUILD", f"building {n_tubes} transfer request(s) ...")
        transfers = build_transfer_requests(flat, df, lot_ids, container_ids)
        log(stage := "BENCHLING_PUSH", f"transferring lots into {n_tubes} containers "
            f"(chunks of {chunk_size}) ...")
        run_bulk(benchling, transfers, "transfers", chunk_size,
                 submit=benchling.containers.transfer_into_containers)

    except Exception as e:
        log(stage, f"FAILED: {e}")
        raise

    log("BENCHLING_PUSH", f"{n_rows} lots / {n_tubes} tubes uploaded")
    return 0


def parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Push a GenScript antibody order CSV to Benchling (test tenant).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--csv", required=True)
    p.add_argument("--env", choices=["test", "prod"], default="test",
                   help="Prod has no GenScript schemas yet, so prod uploads will fail.")
    p.add_argument("--location", required=True, metavar="LOC_ID",
                   help="Benchling location id (loc_…) where new boxes will be placed.")
    p.add_argument("--batch-size", type=int, default=BATCH_SIZE_DEFAULT,
                   help="Max items per bulk_create / transfer chunk (Benchling caps at 100).")
    return p.parse_args(argv)


def main() -> int:
    load_dotenv()
    args = parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        sys.exit(f"[LOCAL_PARSE] ERROR: CSV not found: {csv_path}")

    df = read_csv(csv_path)
    tubes_by_row = build_tubes(df)
    validate_tubes(tubes_by_row)
    n_tubes = sum(len(t) for t in tubes_by_row)
    log("LOCAL_PARSE", f"loaded {len(df)} lot row(s) -> {n_tubes} tube(s) from {csv_path}")

    benchling = connect(args.env)
    log("BENCHLING_PUSH", f"connected to {args.env} tenant")
    registry_id = benchling.registry.registries()[0].id
    log("BENCHLING_PUSH", f"registry: {registry_id}")

    container_type_id = resolve_dropdown(benchling, "Container Type", CONTAINER_TYPE)
    log("BENCHLING_PUSH", f"container type {CONTAINER_TYPE!r} -> {container_type_id}")

    rc = upload(benchling, df, tubes_by_row, registry_id, args.location,
                container_type_id, args.batch_size)

    # Final step of a successful push: stamp the completion marker. Status keys off this, so it
    # must be last — a failure in any earlier phase raises above and never reaches here. A marker
    # write that itself fails doesn't undo a good upload; log it and let a re-run/backfill fix it.
    # The mirror is stamped after, never before, so it can't claim more than the tenant holds.
    if rc == 0:
        prefix = str(df["Order ID"].iloc[0]).split("-", 1)[0]
        try:
            mid = write_marker(benchling, prefix, args.env)
            set_state(args.env, prefix, "complete")
            log("BENCHLING_PUSH", f"upload complete — wrote marker {mid}" if mid
                else "upload complete — markers not configured, none written")
        except Exception as e:
            log("BENCHLING_PUSH", f"WARNING: upload succeeded but marker write failed: {e}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
