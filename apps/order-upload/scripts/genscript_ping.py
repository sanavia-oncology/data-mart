"""Read-only by default: does this tenant's API key authenticate? Prints JSON {ok, reason}.

The app's connection pill. --write also proves the key can push: it creates a throwaway folder
under the marker parent and archives it straight away — the same write the uploader's final step
makes, so a read-only key is caught here instead of 90 seconds into an upload.
"""

import argparse
import json
import sys
import time

from dotenv import load_dotenv
from benchling_sdk.models import FolderCreate, FoldersArchiveReason

from benchling_io import connect
from genscript_marker import PROBE_PREFIX, marker_parent_id


def _reason(e: Exception) -> str:
    txt = str(e)
    if "401" in txt or "authenticate" in txt.lower():
        return "key rejected (401)"
    if "403" in txt or "permission" in txt.lower():
        return "no access (403)"
    if any(s in txt for s in ("Timeout", "ConnectError", "nodename", "Name or service")):
        return "cannot reach Benchling"
    return type(e).__name__


def check(env: str, write: bool = False) -> dict:
    try:
        benchling = connect(env)
    except SystemExit:                                  # connect() exits on a missing var
        return {"ok": False, "reason": "credentials missing"}
    try:
        benchling.registry.registries()                 # cheapest call needing a valid key
    except Exception as e:
        return {"ok": False, "reason": _reason(e)}
    if not write:
        return {"ok": True, "reason": ""}

    try:
        parent = marker_parent_id(benchling, env)
    except Exception as e:
        return {"ok": False, "reason": f"marker folder: {e}"}
    try:
        folder = benchling.folders.create(
            FolderCreate(name=PROBE_PREFIX + time.strftime("%H%M%S"), parent_folder_id=parent))
    except Exception as e:
        return {"ok": False, "reason": f"cannot push — {_reason(e)}"}
    try:
        benchling.folders.archive([folder.id], FoldersArchiveReason.MADE_IN_ERROR)
    except Exception:
        pass                                            # a stray probe folder is harmless
    return {"ok": True, "reason": ""}


def main() -> int:
    load_dotenv()
    p = argparse.ArgumentParser(description="Check the tenant's API key authenticates (and can push).")
    p.add_argument("--env", choices=["test", "prod"], default="test")
    p.add_argument("--write", action="store_true", help="also prove the key can create/archive.")
    args = p.parse_args()
    json.dump(check(args.env, args.write), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
