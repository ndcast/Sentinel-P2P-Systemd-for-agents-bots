#!/bin/bash
# Sentinel dVPN Disconnect — clean teardown of WireGuard + leftover processes
# Matches the style and variable handling of sentinel-connect.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment if available (same fallback pattern as connect script)
if [[ -f "${SCRIPT_DIR}/sentinel-env.sh" ]]; then
  source "${SCRIPT_DIR}/sentinel-env.sh"
elif [[ -f "${HOME}/sentinel-dvpncli/sentinel-env.sh" ]]; then
  source "${HOME}/sentinel-dvpncli/sentinel-env.sh"
fi

# Work dir (same default as connect script)
WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
WG_CONF="${WORK_DIR}/wireguard/wg0.conf"

echo "[$(date '+%H:%M:%S')] Stopping Sentinel dVPN..."

# 1. Bring down WireGuard interface using the actual config file
if [[ -f "$WG_CONF" ]]; then
  echo "[$(date '+%H:%M:%S')] Bringing down WireGuard interface (config: $WG_CONF)"
  if sudo wg-quick down "$WG_CONF"; then
    echo "[$(date '+%H:%M:%S')] ✓ WireGuard interface removed"
  else
    echo "[$(date '+%H:%M:%S')] ⚠ wg-quick down failed or interface already down"
  fi
else
  echo "[$(date '+%H:%M:%S')] ⚠ No wg0.conf found at $WG_CONF — skipping wg-quick"
fi

# 2. Kill any remaining sentinel-dvpncli connect processes
echo "[$(date '+%H:%M:%S')] Cleaning up sentinel-dvpncli processes..."
pkill -f "sentinel-dvpncli connect" 2>/dev/null || true
pkill -f "sentinel-connect.sh" 2>/dev/null || true
pkill -f "sentinel-wg-monitord.sh" 2>/dev/null || true

# 3. Final verification
sleep 1
if pgrep -f "sentinel-dvpncli connect" >/dev/null || pgrep -f "sentinel-connect.sh" >/dev/null; then
  echo "[$(date '+%H:%M:%S')] ⚠ Some processes may still be running"
else
  echo "[$(date '+%H:%M:%S')] ✓ All Sentinel dVPN processes terminated"
fi

echo "[$(date '+%H:%M:%S')] Sentinel dVPN disconnect complete."