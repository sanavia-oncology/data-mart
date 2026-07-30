"""Read-only: print JSON [{id, name}] of Benchling storage locations for the app dropdown."""

import argparse
import json
import sys

from dotenv import load_dotenv

from benchling_io import connect


def list_locations(benchling) -> list[dict]:
    out = []
    for page in benchling.locations.list():
        for loc in page:
            if getattr(loc, "archive_record", None) is None:
                out.append({"id": loc.id, "name": loc.name or loc.id})
    return out


def parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="List Benchling storage locations (read-only).")
    p.add_argument("--env", choices=["test", "prod"], default="test")
    return p.parse_args(argv)


def main() -> int:
    load_dotenv()
    args = parse_args()
    benchling = connect(args.env)
    json.dump(list_locations(benchling), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
