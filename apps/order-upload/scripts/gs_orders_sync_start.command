#!/usr/bin/env zsh
# Double-click once, from anywhere: copies itself to ~/.order-upload/ and registers a launchd agent that runs the copy at every login.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # Finder doesn't inherit a Terminal PATH

LABEL="com.sanavia.gs-orders-sync"
STATE="${ORDER_UPLOAD_STATE_DIR:-$HOME/.order-upload}"
LOGS="${ORDER_UPLOAD_LOG_DIR:-$HOME/Library/Logs/order-upload}"
ENV_FILE="${DATA_MART_ENV_FILE:-$HOME/.env_data_mart_order_upload}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
COPY="$STATE/gs_orders_sync.command"
LOG="$LOGS/gs_orders_sync.log"

# env file: GS_ORDERS_DIR, optional GS_ORDERS_SYNC_INTERVAL / GS_ORDERS_AWS_CREDS_FILE / AWS_PROFILE; the creds file names its own bucket
load_config() {
    set -a; . "$ENV_FILE"; set +a
    CREDS="${GS_ORDERS_AWS_CREDS_FILE:-$STATE/aws-creds}"; CREDS="${CREDS/#\~/$HOME}"
    if [[ -z "${AWS_PROFILE:-}" && -f "$CREDS" ]]; then set -a; . "$CREDS"; set +a; fi
    ROOT="${GS_ORDERS_DIR:-}"; ROOT="${ROOT/#\~/$HOME}"; ROOT="${ROOT%/}"
    BUCKET="${GS_ORDERS_S3_BUCKET:-sanavia-experiment-raw-data}"
    PREFIX="${GS_ORDERS_S3_PREFIX-genscript-orders/}"
    INTERVAL="${GS_ORDERS_SYNC_INTERVAL:-30}"
    case "$INTERVAL" in ''|*[^0-9]*) INTERVAL=30 ;; esac
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
}

run_sync() {
    set -uo pipefail
    mkdir -p "$STATE" "$LOGS"
    log() { printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }

    # every order folder goes up, Legacy included; only the Benchling app skips Legacy. Junk excludes last: the last match wins
    EXCLUDES=(
        --exclude "*" --include "[0-9][0-9][0-9][0-9]-[0-9][0-9]/*" --include "Legacy/*"
        --exclude "*.DS_Store"
        --exclude "._*"        --exclude "*/._*"
        --exclude "Icon*"      --exclude "*/Icon*"
        --exclude "Thumbs.db"  --exclude "*/Thumbs.db"
        --exclude "~\$*"       --exclude "*/~\$*"
        --exclude ".~lock*"    --exclude "*/.~lock*"
        --exclude ".git/*"     --exclude "*/.git/*"
    )

    CHILD=""
    trap 'kill -KILL "$CHILD" 2>/dev/null; rm -f "$STATE/gs_orders_sync.pid"; log "stopped"; exit 0' INT TERM
    echo $$ > "$STATE/gs_orders_sync.pid"
    log "--- start (pid $$)"

    while true; do
        # re-read every pass so env or key edits apply without a restart
        if [[ -f "$ENV_FILE" ]]; then
            load_config
        else
            log "ERROR no env file at $ENV_FILE"; sleep 60; continue
        fi

        if [[ -z "$ROOT" ]]; then
            log "ERROR GS_ORDERS_DIR is not set in $ENV_FILE"
        elif [[ ! -d "$ROOT" ]]; then
            log "ERROR missing folder: $ROOT"
        elif [[ -z "${AWS_PROFILE:-}" && ! -f "$CREDS" ]]; then
            log "ERROR no key at $CREDS"
        else
            args=(s3 sync "$ROOT" "s3://$BUCKET/$PREFIX"
                  --no-progress --only-show-errors "${EXCLUDES[@]}"
                  --cli-connect-timeout 10 --cli-read-timeout 120)
            # never --delete: a local wipe must not reach the bucket
            if printf '%s\n' "${args[@]}" | grep -qx -- "--delete"; then
                log "REFUSING: --delete present in sync args"
            else
                aws "${args[@]}" >>"$LOG" 2>&1 &   # backgrounded so a signal reaches us mid-transfer
                CHILD=$!
                if wait "$CHILD"; then log "ok $ROOT"; else log "ERROR sync failed: $ROOT"; fi
                CHILD=""
            fi
        fi

        if [[ $(stat -f%z "$LOG" 2>/dev/null || echo 0) -gt 1048576 ]]; then
            tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
        fi

        sleep "$INTERVAL" &   # backgrounded so a signal lands immediately
        wait $! || break
    done
}

[[ "${1:-}" == "--run" ]] && { run_sync; exit 0; }

set -eo pipefail
command -v aws >/dev/null 2>&1 || { print -u2 "aws not found - brew install awscli"; exit 1; }
[[ -f "$ENV_FILE" ]] || { print -u2 "no $ENV_FILE"; exit 1; }
mkdir -p "$STATE" "$LOGS" "$HOME/Library/LaunchAgents"

# adopt a key dropped next to this file, so nothing secret stays in Downloads
here="${0:A:h}"
if [[ -f "$here/aws-creds" && "$here/aws-creds" != "$STATE/aws-creds" ]]; then
    mv -f "$here/aws-creds" "$STATE/aws-creds"; chmod 600 "$STATE/aws-creds"
fi

load_config
[[ -n "$ROOT" ]] || { print -u2 "GS_ORDERS_DIR is not set in $ENV_FILE"; exit 1; }
[[ -d "$ROOT" ]] || { print -u2 "GS_ORDERS_DIR is not a folder: $ROOT"; exit 1; }
[[ -n "${AWS_PROFILE:-}" || -f "$CREDS" ]] || { print -u2 "no key: save aws-creds next to this file, or at $CREDS"; exit 1; }

cp "${0:A}" "$COPY"; chmod 755 "$COPY"   # launchd runs the copy directly, so Login Items shows its name, and this file can live anywhere

# KeepAlive, not StartInterval: the loop paces itself
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$COPY</string><string>--run</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key><string>$HOME</string>
        <key>DATA_MART_ENV_FILE</key><string>$ENV_FILE</string>
        <key>ORDER_UPLOAD_STATE_DIR</key><string>$STATE</string>
        <key>ORDER_UPLOAD_LOG_DIR</key><string>$LOGS</string>
    </dict>
    <key>StandardOutPath</key><string>$LOGS/launchd.out.log</string>
    <key>StandardErrorPath</key><string>$LOGS/launchd.err.log</string>
    <key>ProcessType</key><string>Background</string>
    <key>LowPriorityIO</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null || { print -u2 "bad plist at $PLIST"; rm -f "$PLIST"; exit 1; }

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true   # or a changed plist is ignored
for _ in {1..40}; do launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 || break; sleep 0.25; done   # bootout returns before the old one is gone
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$UID/$LABEL" 2>/dev/null || true   # bootstrap alone waits for the next login

print "syncing: $ROOT"
print "     to: s3://$BUCKET/$PREFIX"
print "\nlog:  $LOG"
print "stop: gs_orders_sync_stop.command"
