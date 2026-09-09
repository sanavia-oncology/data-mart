#!/usr/bin/env zsh
PORTS=(3005 3004)   # same pair the updater stops — order-upload and merge-order-sheets

# -sTCP:LISTEN or this also matches browser tabs connected to the app.
listeners() { lsof -t -i :$1 -sTCP:LISTEN 2>/dev/null }

for port in $PORTS; do
  pids=$(listeners $port)
  [[ -z "$pids" ]] && { print "nothing listening on $port"; continue }

  kill $pids 2>/dev/null
  for _ in {1..10}; do          # 3s to exit cleanly, then force it
    sleep 0.3
    pids=$(listeners $port)
    [[ -z "$pids" ]] && break
  done
  [[ -n "$pids" ]] && { kill -9 $pids 2>/dev/null; sleep 0.5; pids=$(listeners $port) }

  [[ -z "$pids" ]] && print "stopped the app on $port" || print -u2 "could not stop $port ($pids)"
done
