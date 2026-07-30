"""One-time: write completion markers for orders already fully uploaded before markers existed.

An order is marked only if its Benchling lots AND containers both match the CSV's expected counts
(one lot per row, one container per tube) — the thorough check we deliberately don't run on every
status refresh. Legacy orders that fail this stay unmarked (status will show them as partial).

  python scripts/dev-tools/backfill_markers.py --order U0000AAAA0=examples/.../U0000..._sheets.csv --env test
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from dotenv import load_dotenv

from benchling_io import connect
from genscript_marker import has_marker, marker_parent_id, write_marker
from genscript_parse import SCHEMAS, build_tubes, read_csv


def _count(page_iter, prefix: str) -> int:
    return sum(1 for page in page_iter for x in page
               if getattr(x, "archive_record", None) is None and (x.name or "").startswith(prefix))


def main() -> int:
    load_dotenv()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--order", dest="orders", action="append", required=True, metavar="PREFIX=CSV")
    ap.add_argument("--env", choices=["test", "prod"], default="test")
    args = ap.parse_args()

    if marker_parent_id(args.env) is None:
        sys.exit(f"ERROR: GENSCRIPT_{args.env.upper()}_MARKER_FOLDER_ID not set")

    b = connect(args.env)
    for spec in args.orders:
        prefix, _, csv = spec.partition("=")
        prefix = prefix.strip().split("-", 1)[0]
        if has_marker(b, prefix, args.env):
            print(f"{prefix}: already marked — skip")
            continue
        df = read_csv(Path(csv.strip()))
        exp_lots, exp_tubes = len(df), sum(len(t) for t in build_tubes(df))
        lots = _count(b.custom_entities.list(schema_id=SCHEMAS["lot"], name_includes=prefix), prefix)
        conts = _count(b.containers.list(schema_id=SCHEMAS["container"], name_includes=prefix), prefix)
        if lots >= exp_lots and conts >= exp_tubes:
            mid = write_marker(b, prefix, args.env)
            print(f"{prefix}: complete ({lots}/{exp_lots} lots, {conts}/{exp_tubes} tubes) -> marked {mid}")
        else:
            print(f"{prefix}: INCOMPLETE ({lots}/{exp_lots} lots, {conts}/{exp_tubes} tubes) -> left unmarked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
