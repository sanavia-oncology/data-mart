#!/usr/bin/env bash
# Launch GenScript Orders (plain Shiny). Usage: ./scripts/run.sh [PORT]   (default 5041)
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${1:-5041}"
echo "GenScript Orders → http://127.0.0.1:${PORT}"
exec R --quiet -e "shiny::runApp('.', host='127.0.0.1', port=${PORT})"
