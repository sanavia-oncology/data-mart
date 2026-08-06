#!/usr/bin/env zsh
set -eo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # a Finder launch doesn't inherit a Terminal PATH

REPO_URL="https://github.com/sanavia-oncology/data-mart.git"
ROOT="$HOME/sanavia-apps"
REPO="$ROOT/data-mart"
APP="$REPO/apps/order-upload"
PORT=3005

# Running the in-repo copy would delete this file while the shell is still reading it.
if [[ "${0:A}" == "$REPO"/* ]]; then
  print -u2 "run this copy from outside $REPO — the update deletes that directory"
  exit 1
fi

for tool in git python3; do
  command -v "$tool" >/dev/null 2>&1 || { print -u2 "$tool not found in PATH"; exit 1; }
done

pids=$(lsof -t -i :$PORT -sTCP:LISTEN 2>/dev/null || true)
if [[ -n "$pids" ]]; then
  print "stopping the app on $PORT"
  kill $pids 2>/dev/null || true
  sleep 1
fi

mkdir -p "$ROOT"
rm -rf "$REPO"
git clone --depth 1 "$REPO_URL" "$REPO"

[[ -f "$APP/requirements.txt" ]] || { print -u2 "no requirements.txt at $APP after clone"; exit 1; }

ln -sf "$HOME/.env_benchling" "$APP/.env"
python3 -m venv "$APP/benchling-python-env"
"$APP/benchling-python-env/bin/pip" install --quiet --upgrade pip
"$APP/benchling-python-env/bin/pip" install -r "$APP/requirements.txt"

print "updated: $APP"
