"""The sync: print JSON of each --order-id's GenScript upload state in Benchling, and rewrite the
local mirror (logs/status-<env>.json) from it. Read-only against the tenant.

State per order:
  none      no completion marker and no lots         -> not uploaded
  complete  a completion marker folder exists          -> fully uploaded
  partial   lots exist but no marker                    -> a half-finished / failed push

The marker (see genscript_marker.py) is the whole signal — one listing of the marker folder
settles every complete order in the batch, no counting. Only an order *without* a marker does a
single first-page "does any lot exist?" probe (stops at the first hit) to tell a failed push from
one never started.
"""

import argparse
import json
import sys

from dotenv import load_dotenv

from benchling_io import connect
from genscript_marker import list_markers
from genscript_parse import SCHEMAS
from genscript_status_cache import entry, write_states


def has_any_lot(benchling, prefix: str) -> bool:
    """True if at least one active lot for the order exists. Stops on the first match — one page,
    not a full count."""
    for page in benchling.custom_entities.list(schema_id=SCHEMAS["lot"], name_includes=prefix):
        for lot in page:
            if getattr(lot, "archive_record", None) is None and (lot.name or "").startswith(prefix):
                return True
    return False


def parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Report each GenScript order's upload state in Benchling (read-only).")
    p.add_argument("--order-id", dest="order_ids", action="append", required=True,
                   help="Bare order-id prefix, e.g. U0000AAAA0. Repeatable.")
    p.add_argument("--env", choices=["test", "prod"], default="test")
    p.add_argument("--no-cache", action="store_true",
                   help="Print the states without refreshing the local mirror.")
    return p.parse_args(argv)


def main() -> int:
    load_dotenv()
    args = parse_args()
    benchling = connect(args.env)
    markers = list_markers(benchling, args.env)      # one call for the batch; None = not configured
    out = {}
    for oid in args.order_ids:
        prefix = oid.strip().split("-", 1)[0]
        if markers is not None and prefix in markers:  # marker present -> done, no lot probe
            state = "complete"
        else:
            has_lot = has_any_lot(benchling, prefix)
            if markers is None:                      # markers not configured -> can't detect partial
                state = "complete" if has_lot else "none"
            else:
                state = "partial" if has_lot else "none"
        out[prefix] = {"state": state, "uploaded": state == "complete"}
    if not args.no_cache:
        write_states(args.env, {p: entry(v["state"]) for p, v in out.items()})
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
