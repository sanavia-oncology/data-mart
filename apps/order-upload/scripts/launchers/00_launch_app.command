#!/usr/bin/env zsh
set -eo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # a Finder launch doesn't inherit a Terminal PATH

APP="$HOME/sanavia-apps/data-mart/apps/order-upload"
PORT=3005

[[ -f "$APP/server.R" ]] || { print -u2 "no app at $APP — run 02_update.command first"; exit 1; }

R_BIN=$(command -v R || true)
[[ -x "$R_BIN" ]] || R_BIN="/Library/Frameworks/R.framework/Resources/bin/R"
[[ -x "$R_BIN" ]] || { print -u2 "R not found — install it from https://cran.r-project.org"; exit 1; }

trap 'kill $(jobs -p) 2>/dev/null' INT TERM EXIT

APP_DIR="$APP" "$R_BIN" --quiet -e "shiny::runApp(Sys.getenv('APP_DIR'), host='127.0.0.1', port=$PORT, launch.browser=FALSE)" &

wait
