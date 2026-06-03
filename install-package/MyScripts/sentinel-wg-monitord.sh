#!/bin/bash
# sentinel-wg-monitord-v3.sh — Simple SUPPRESS_PRIORITY monitor
# Watches for the suppress_prefixlength rule (created by wg-quick)
# When it appears or disappears → runs the bypass script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BYPASS_SCRIPT="${SCRIPT_DIR}/sentinel-ip-vpnbypass.sh"
PID_FILE="${HOME}/sentinel-dvpncli/sentinel-wg-monitord.pid"
POLL_INTERVAL=10

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

get_suppress_priority() {
    sudo ip rule show | grep -o '^[0-9]*:' | head -1 || true
}

run_bypass() {
    if [[ -x "$BYPASS_SCRIPT" ]]; then
        "$BYPASS_SCRIPT" || log "bypass exited non-zero"
    fi
}

cleanup() {
    log "stopping"
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup EXIT SIGTERM SIGINT

# single instance guard
if [[ -f "$PID_FILE" ]]; then
    OLD=$(cat "$PID_FILE")
    if kill -0 "$OLD" 2>/dev/null; then
        log "already running"
        exit 1
    fi
    rm -f "$PID_FILE"
fi

echo $$ > "$PID_FILE"
log "started (PID $$)"

SUPPRESS_WAS_PRESENT=false

while true; do
    SUPPRESS_PRIORITY=$(sudo ip rule show | grep -o 'suppress_prefixlength' || true)

    if [[ -n "$SUPPRESS_PRIORITY" ]]; then
        if [ "$SUPPRESS_WAS_PRESENT" = false ]; then
            log "suppress rule appeared → running bypass"
            run_bypass
            SUPPRESS_WAS_PRESENT=true
        fi
    else
        if [ "$SUPPRESS_WAS_PRESENT" = true ]; then
            log "suppress rule gone → running bypass"
            run_bypass
            SUPPRESS_WAS_PRESENT=false
        fi
    fi

    sleep "$POLL_INTERVAL"
done

