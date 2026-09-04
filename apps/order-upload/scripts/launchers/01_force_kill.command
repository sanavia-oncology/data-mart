#!/usr/bin/env zsh
PORTS=(3005 3004)   # same pair the updater stops — order-upload and merge-order-sheets

# -sTCP:LISTEN or this also matches browser tabs connected to the app.
listeners() { lsof -t -i :$1 -sTCP:LISTEN 2>/dev/null }

failed=0
for port in $PORTS; do
  pids=$(listeners $port)
  if [[ -z "$pids" ]]; then
    print "nothing listening on $port"
    continue
  fi

  kill $pids 2>/dev/null
  for _ in {1..10}; do          # give it 3s to go down cleanly
    sleep 0.3
    pids=$(listeners $port)
    [[ -z "$pids" ]] && break
  done

  if [[ -n "$pids" ]]; then     # SIGTERM ignored — this is the "force" the name promises
    kill -9 $pids 2>/dev/null
    sleep 0.5
    pids=$(listeners $port)
  fi

  if [[ -n "$pids" ]]; then
    print -u2 "could not stop $port (pids: $pids)"
    failed=1
  else
    print "stopped the app on $port"
  fi
done
exit $failed
