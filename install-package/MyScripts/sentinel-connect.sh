#!/bin/bash
# Sentinel dVPN Auto-Connect — error handling + provider fault detection + blacklist

# Load shared library (country codes, blacklist helpers)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/sentinel-node-lib.sh" ]]; then
  source "${SCRIPT_DIR}/sentinel-node-lib.sh"
elif [[ -f "${HOME}/sentinel-dvpncli/sentinel-env.sh" ]]; then
  source "${HOME}/sentinel-dvpncli/sentinel-env.sh"
fi

# Defaults
WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
RPC="${RPC_ENDPOINTS:-https://sentinel-rpc.polkachu.com:443,https://sentinel-rpc.publicnode.com:443}"
LCD="${LCD_ENDPOINT:-https://lcd.sentinel.co}"
KEYRING_BACKEND="${KEYRING_BACKEND:-test}"
KEYRING_HOME="${KEYRING_HOME:-$WORK_DIR}"
KEY_NAME="${KEY_NAME:-main}"
FALLBACK_NODES_FILE="${HOME}/fav-providers.lst"
BEST_FILE="${HOME}/.best-sentinel-node"
BLACKLIST_FILE="${WORK_DIR}/blacklist-nodes.lst"

# Load countries
node_lib_load_countries

# Address from keyring
ADDRESS=$(cat "${WORK_DIR}/.address" 2>/dev/null | cut -d '"' -f2 | xargs)
if [ -z "$ADDRESS" ]; then
  echo "[$(date '+%H:%M:%S')] ❌ No address found (${WORK_DIR}/.address is empty or missing)"
  exit 1
fi

# -----------------------------
# Helper: start a session and capture its ID
# Returns: prints session ID on success, exits on failure
# -----------------------------
create_new_session() {
  local NODE="$1"
  local TX_OUTPUT

  TX_OUTPUT=$(sentinel-dvpncli tx session-start "$NODE" \
    --tx.from-name "$KEY_NAME" \
    --keyring.backend "$KEYRING_BACKEND" \
    --home "$KEYRING_HOME" \
    --rpc.addrs "$RPC" \
    --tx.gas-prices "${TX_GAS_PRICES:-0.1udvpn}" \
    --tx.gas-adjustment "${TX_GAS_ADJUSTMENT:-1.8}" \
    --max-price "${MAX_PRICE:-udvpn:1,30000}" \
    --gigabytes "${DEFAULT_GIGABYTES:-10}" \
    --hours "${DEFAULT_HOURS:-0}" 2>&1)


  # Check for insufficient funds
  if echo "$TX_OUTPUT" | grep -qiE "insufficient|not enough|too low|cannot pay"; then
    echo "[$(date '+%H:%M:%S')] ❌ ERROR: Insufficient funds — add DVPN to your wallet"
    echo "   Address: $ADDRESS"
    exit 1
  fi

  # Extract session ID from output
  # Extract session ID from JSON log field via jq
  local SESSION_ID
  SESSION_ID=$(echo "$TX_OUTPUT" | \
    sed -n 's/.*"log": *//p' | \
    jq -r '.[0].events[] | select(.type == "sentinel.node.v3.EventCreateSession") | .attributes[] | select(.key == "session_id") | .value' 2>/dev/null | tr -d '"')

  # Fallback if jq fails
  if [ -z "$SESSION_ID" ] || ! [[ "$SESSION_ID" =~ ^[0-9]+$ ]]; then
    SESSION_ID=$(echo "$TX_OUTPUT" | grep -o 'session_id[^0-9]*[0-9]\+' | grep -o '[0-9]\+' | tail -n1)
  fi

  # Probe if not in output
  if [ -z "$SESSION_ID" ]; then
    sleep 10
    SESSION_ID=$(sentinel-dvpncli query sessions \
      --account-addr "$ADDRESS" \
      --rpc.addrs "$RPC" 2>/dev/null | \
      awk '/id: [0-9.]+e\+[0-9]+/ {split($NF,a,"e+"); printf "%.0f\n", a[1]*(10^a[2])}' | head -n1)
  fi

  if [ -z "$SESSION_ID" ]; then
    echo "[$(date '+%H:%M:%S')] ❌ Failed to create session with $NODE — no session ID returned"
    return 1
  fi

  echo "$SESSION_ID"
}

# Parse -f flag
USE_FAV=false
if [[ "$1" == "-f" ]]; then
  USE_FAV=true
fi

echo "[$(date '+%H:%M:%S')] Starting Sentinel dVPN..."

# -----------------------------
# Node selection (supports fav file, cached best, or re-run selector)
# -----------------------------
if [ "$USE_FAV" = true ] && [ -f "$FALLBACK_NODES_FILE" ]; then
  NODE=$(shuf -n1 "$FALLBACK_NODES_FILE" | tr -d '[:space:]')
  echo "[$(date '+%H:%M:%S')] Using favorite node: $NODE"
elif [ -f "$BEST_FILE" ]; then
  NODE=$(cat "$BEST_FILE" | tr -d '[:space:]')
  echo "[$(date '+%H:%M:%S')] Using cached best node: $NODE"
else
  echo "[$(date '+%H:%M:%S')] No node found — running sentinel-select-best-node.sh..."
  NODE=$(bash "${SCRIPT_DIR}/sentinel-select-best-node.sh" 2>/dev/null | grep "Selected node:" | awk '{print $3}')
  if [ -z "$NODE" ]; then
    echo "[$(date '+%H:%M:%S')] ❌ Could not select a node"
    exit 1
  fi
fi

# Verify node is not blacklisted
if is_blacklisted "$NODE"; then
  echo "[$(date '+%H:%M:%S')] ⚠️  Cached node $NODE is blacklisted — re-selecting..."
  NODE=$(bash "${SCRIPT_DIR}/sentinel-select-best-node.sh" 2>/dev/null | grep "Selected node:" | awk '{print $3}')
  if [ -z "$NODE" ]; then
    echo "[$(date '+%H:%M:%S')] ❌ No non-blacklisted nodes available"
    exit 1
  fi
fi

# -----------------------------
# Balance check
# -----------------------------
echo "[$(date '+%H:%M:%S')] Checking balance..."
BALANCE_UDVPN=$(curl -s "${LCD}/cosmos/bank/v1beta1/balances/${ADDRESS}" \
  | jq -r '.balances[]? | select(.denom == "udvpn") | .amount' 2>/dev/null || echo "0")
BALANCE_DVPN=$((BALANCE_UDVPN / 1000000))
echo "   Balance: ${BALANCE_DVPN} DVPN"

if [ "$BALANCE_UDVPN" -lt 1000000 ]; then
  echo "[$(date '+%H:%M:%S')] ❌ ERROR: Insufficient balance (${BALANCE_DVPN} DVPN — minimum ~1 DVPN needed)"
  exit 1
fi

# -----------------------------
# Cancel any existing sessions first
# -----------------------------
echo "[$(date '+%H:%M:%S')] Cancelling any existing sessions..."
sentinel-dvpncli tx session-cancel --all \
  --keyring.name "$KEY_NAME" \
  --keyring.backend "$KEYRING_BACKEND" \
  --home "$KEYRING_HOME" \
  --rpc.addrs "$RPC" \
  --tx.gas-prices "${TX_GAS_PRICES:-0.1udvpn}" \
  --tx.gas-adjustment "${TX_GAS_ADJUSTMENT:-1.8}" 2>/dev/null || true

sleep 2

# -----------------------------
# Start new session (via helper)
# -----------------------------
NEW_SESSION=$(create_new_session "$NODE") || exit 1
echo "[$(date '+%H:%M:%S')] ✅ Session $NEW_SESSION created. Connecting..."

# -----------------------------
# Connect with retry + WG health check
# -----------------------------
MAX_ATTEMPTS=6
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  echo "[$(date '+%H:%M:%S')] Connect attempt $ATTEMPT of $MAX_ATTEMPTS..."

  # Parse sentinel-dvpncli connect exit codes:
  #   0  = tunnel came up (or daemon is running — see WG_UP check below)
  #   1  = error
  #   2  = session not yet active on-chain ("inactive_pending" / "active" mismatch)
  #      → cancel session, create new one, retry connect; NOT a provider fault
  #
  # Provider fault (true failure):
  #   connect exits 0 AND WG_UP check fails (WG exists but no inet address)
  #   → blacklist node, re-select, cancel session, create fresh session

  CONNECT_OUTPUT=""
  CONNECT_EXIT=0
  sentinel-dvpncli connect "$NEW_SESSION" \
    --home "$KEYRING_HOME" \
    --keyring.backend "$KEYRING_BACKEND" \
    --keyring.name "$KEY_NAME" 2>&1 | tee /tmp/sentinel-connect-attempt-${ATTEMPT}.log
  CONNECT_EXIT=${PIPESTATUS[0]}

  # Case 1: connect exited 2 = session not active on-chain yet
  if [ $CONNECT_EXIT -eq 2 ]; then
    # Check if it's the "inactive_pending" error (session not ready)
    CONNECT_OUTPUT=$(cat /tmp/sentinel-connect-attempt-${ATTEMPT}.log)
    if echo "$CONNECT_OUTPUT" | grep -qiE 'inactive_pending|invalid session status.*expected.*active'; then
      echo "[$(date '+%H:%M:%S')] ⏳ Session not active yet (inactive_pending) — retrying in 8s..."
    else
      echo "[$(date '+%H:%M:%S')] ⏳ Connect exited code 2 — retrying in 8s..."
    fi
    sleep 8
    ATTEMPT=$((ATTEMPT + 1))
    continue
  fi

  # Case 2: connect exited non-zero (other error)
  if [ $CONNECT_EXIT -ne 0 ]; then
    echo "[$(date '+%H:%M:%S')] ⏳ Connect failed (exit $CONNECT_EXIT) — retrying in 5s..."
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
    continue
  fi

  # Case 3: connect exited 0 — verify WG tunnel is actually up
  # We require BOTH the interface to exist AND an inet address to be assigned.
  # "ip link show wg0" alone is insufficient — interface can exist without any IP.
  sleep 3
  WG_UP=false
  if ip addr show wg0 2>/dev/null | grep -q "inet "; then
    # Also verify wg show reports at least one peer or a working handshake
    if wg show wg0 2>/dev/null | grep -qE "peer:|endpoint:"; then
      WG_UP=true
    fi
  fi

  if [ "$WG_UP" = true ]; then
    echo "[$(date '+%H:%M:%S')] ✅ Connected successfully (WG interface: wg0)"
	sleep 10
	bash "${SCRIPT_DIR}/sentinel-ip-vpnbypass.sh"
    exit 0
  else
    echo "[$(date '+%H:%M:%S')] ⚠️  Provider fault detected: blockchain session active but WG tunnel did not come up"
    echo "[$(date '+%H:%M:%S')]    Blacklisting node: $NODE"
    blacklisted_add "$NODE" "provider fault: WG tunnel failed post-connect"
    echo "[$(date '+%H:%M:%S')]    Re-selecting a different node..."

    NEW_NODE=$(bash "${SCRIPT_DIR}/sentinel-select-best-node.sh" 2>/dev/null \
      | grep "Selected node:" | awk '{print $3}')
    if [ -z "$NEW_NODE" ]; then
      echo "[$(date '+%H:%M:%S')] ❌ No non-blacklisted nodes available"
      exit 1
    fi
    NODE="$NEW_NODE"
    echo "[$(date '+%H:%M:%S')]    New node: $NODE"

    sentinel-dvpncli tx session-cancel "$NEW_SESSION" \
      --keyring.name "$KEY_NAME" \
      --keyring.backend "$KEYRING_BACKEND" \
      --home "$KEYRING_HOME" \
      --rpc.addrs "$RPC" \
      --tx.gas-prices "${TX_GAS_PRICES:-0.1udvpn}" \
      --tx.gas-adjustment "${TX_GAS_ADJUSTMENT:-1.8}" 2>/dev/null || true

    NEW_SESSION=$(create_new_session "$NODE") || exit 1
    echo "[$(date '+%H:%M:%S')] ✅ New session $NEW_SESSION started with node $NODE"
    sleep 2
    ATTEMPT=1
    continue
  fi
done

echo "[$(date '+%H:%M:%S')] ❌ All $MAX_ATTEMPTS connect attempts failed."
echo "[$(date '+%H:%M:%S')]    Blacklisting node due to repeated failures: $NODE"
blacklisted_add "$NODE" "repeated connection failures after $MAX_ATTEMPTS attempts"

# Attempt one fallback to another node (if using favorites or best-node cache)
if [ "$USE_FAV" = true ] && [ -f "$FALLBACK_NODES_FILE" ]; then
  echo "[$(date '+%H:%M:%S')]    Attempting fallback to another favorite provider..."
  while true; do
    NODE=$(shuf -n1 "$FALLBACK_NODES_FILE" | tr -d '[:space:]')
    if [ -z "$NODE" ]; then
      echo "[$(date '+%H:%M:%S')]    No nodes left in favorites file"
      break
    fi
    if ! is_blacklisted "$NODE"; then
      echo "[$(date '+%H:%M:%S')]    Fallback node selected: $NODE"
      break
    fi
    echo "[$(date '+%H:%M:%S')]    Skipping blacklisted favorite: $NODE"
  done
elif [ -f "$BEST_FILE" ]; then
  echo "[$(date '+%H:%M:%S')]    Attempting fallback using best node selector..."
  NODE=$(bash "${SCRIPT_DIR}/sentinel-select-best-node.sh" 2>/dev/null | grep "Selected node:" | awk '{print $3}')
fi

if [ -n "$NODE" ]; then
  echo "[$(date '+%H:%M:%S')]    Fallback node selected: $NODE"
  # Could optionally trigger one more connection attempt here
fi
exit 1
