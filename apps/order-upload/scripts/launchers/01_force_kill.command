#!/usr/bin/env zsh
PORT=3005

# -sTCP:LISTEN or this also matches browser tabs connected to the app.
pids=$(lsof -t -i :$PORT -sTCP:LISTEN 2>/dev/null)
if [[ -n "$pids" ]]; then
  kill $pids 2>/dev/null
  print "stopped the app on $PORT"
else
  print "nothing listening on $PORT"
fi
