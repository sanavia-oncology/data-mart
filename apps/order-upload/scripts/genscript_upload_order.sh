#!/usr/bin/env bash
# genscript_upload_order.sh — update, then run the GenScript order uploader.
#
# Fast-forwards the checkout, syncs the Python env, and runs
# scripts/genscript_order_uploader.py with whatever arguments you pass. That's all
# it does. Anything else you run directly with Python, e.g. cleanup:
#   python scripts/dev-tools/cleanup_run.py --order-id U0000AAAA0 --env test
#
# Usage:
#   ./scripts/genscript_upload_order.sh --csv examples/<order>.csv --env test --location loc_xxxx
set -euo pipefail
cd "$(dirname "$0")/.."                       # app root, wherever you call it from

# Current branch only — never switch, it's a monorepo.
git pull --ff-only \
  || echo "WARNING: could not fast-forward; continuing with the current working tree" >&2

# Fail clearly if python3 is too old — the code uses 3.11+ syntax (str | None, etc.).
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
  || { echo "ERROR: need Python 3.11+, found: $(python3 -V 2>&1)" >&2; exit 1; }

[ -d benchling-python-env ] || python3 -m venv benchling-python-env
source benchling-python-env/bin/activate
pip install --upgrade -r requirements.txt

python scripts/genscript_order_uploader.py "$@"
