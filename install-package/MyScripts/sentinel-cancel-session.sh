#!/bin/bash
# Sentinel Cancel Session Tool

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../sentinel-env.sh" ]]; then
  source "${SCRIPT_DIR}/../sentinel-env.sh"
elif [[ -f "${HOME}/sentinel-dvpncli/sentinel-env.sh" ]]; then
  source "${HOME}/sentinel-dvpncli/sentinel-env.sh"
fi

WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
RPC="${RPC_ENDPOINTS:-https://sentinel-rpc.polkachu.com:443,https://sentinel-rpc.publicnode.com:443}"
KEYRING_BACKEND="${KEYRING_BACKEND:-test}"
KEYRING_HOME="${KEYRING_HOME:-$WORK_DIR}"
KEY_NAME="${KEY_NAME:-main}"
TRACK_FILE="${WORK_DIR}/.sent_sessions"

touch "$TRACK_FILE"
sed -i '/^-f,/d' "$TRACK_FILE" 2>/dev/null

ADDRESS=$(cat "${WORK_DIR}/.address" 2>/dev/null | cut -d '"' -f2 | xargs)

if [ -z "$ADDRESS" ]; then
  echo "❌ No address found (${WORK_DIR}/.address is empty or missing)"
  exit 1
fi

echo "=== Sentinel Session Cancel Tool ==="

if [[ "$1" == "-a" ]]; then
  echo "Mode: Cancel ALL sessions"
  SESSIONS=$(sentinel-dvpncli query sessions \
    --account-addr "$ADDRESS" \
    --rpc.addrs "$RPC" 2>/dev/null | \
    awk '/id: [0-9.]+e\+[0-9]+/ {split($NF,a,"e+"); printf "%.0f\n", a[1]*(10^a[2])}' | sort -nu)
else
  if [ -z "$1" ]; then
    echo "Usage: $0 <session_id>   or   $0 -a"
    exit 1
  fi
  SESSIONS="$1"
  echo "Mode: Cancel single session $SESSIONS"
fi

for ID in $SESSIONS; do
  CURRENT_STATE=$(grep "^$ID," "$TRACK_FILE" 2>/dev/null | cut -d',' -f2)

  if [[ "$CURRENT_STATE" == "inactive_pending" || "$CURRENT_STATE" == "not_found" ]]; then
    echo "[$(date '+%H:%M:%S')] Skipping $ID → already $CURRENT_STATE"
    continue
  fi

  echo "[$(date '+%H:%M:%S')] Cancelling $ID ..."

  echo "$ID,in_process,$(date -u +%Y-%m-%dT%H:%M:%SZ),unknown,unknown" >> "$TRACK_FILE"

  OUTPUT=$(sentinel-dvpncli tx session-cancel "$ID" \
    --tx.from-name "$KEY_NAME" \
    --keyring.backend "$KEYRING_BACKEND" \
    --home "$KEYRING_HOME" \
    --rpc.addrs "$RPC" \
    --tx.gas-prices "${TX_GAS_PRICES:-0.1udvpn}" \
    --tx.gas-adjustment "${TX_GAS_ADJUSTMENT:-1.8}" 2>&1)

  if echo "$OUTPUT" | grep -q "inactive_pending"; then
    STATE="inactive_pending"
    echo "   → Already inactive_pending"
    SLEEP=3
  elif echo "$OUTPUT" | grep -q "does not exist"; then
    STATE="not_found"
    echo "   → Session no longer exists"
    SLEEP=2
  else
    STATE="cancel_attempted"
    echo "   → Cancel command sent"
    SLEEP=8
  fi

  sed -i "/^$ID,/d" "$TRACK_FILE" 2>/dev/null
  echo "$ID,$STATE,$(date -u +%Y-%m-%dT%H:%M:%SZ),unknown,unknown" >> "$TRACK_FILE"

  sleep $SLEEP
done

echo "Finished. Tracked in: $TRACK_FILE"