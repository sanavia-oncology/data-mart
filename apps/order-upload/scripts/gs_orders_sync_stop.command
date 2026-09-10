#!/usr/bin/env zsh
LABEL="com.sanavia.gs-orders-sync"
PIDFILE="${ORDER_UPLOAD_STATE_DIR:-$HOME/.order-upload}/gs_orders_sync.pid"

# read the pid before bootout: launchd's TERM runs the trap that deletes the file
pid=$(cat "$PIDFILE" 2>/dev/null)
running=0
[[ -n "$pid" ]] && ps -p "$pid" -o command= 2>/dev/null | grep -q gs_orders_sync && running=1   # a stale pid may be someone else's

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null   # with KeepAlive, killing the pid alone restarts it
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

if (( running )); then
  for _ in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  kill -0 "$pid" 2>/dev/null && { kill -TERM "$pid" 2>/dev/null; sleep 1; }
  kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null   # SIGKILL skips the trap; take the group or aws lives on
  print "stopped gs_orders_sync (pid $pid)"
else
  print "gs_orders_sync was not running"
fi
rm -f "$PIDFILE"
