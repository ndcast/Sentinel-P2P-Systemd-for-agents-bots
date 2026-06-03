#!/bin/bash
# Sentinel Stale Sessions + Balance Checker

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../sentinel-env.sh" ]]; then
  source "${SCRIPT_DIR}/../sentinel-env.sh"
elif [[ -f "${HOME}/sentinel-dvpncli/sentinel-env.sh" ]]; then
  source "${HOME}/sentinel-dvpncli/sentinel-env.sh"
fi

WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
RPC="${RPC_ENDPOINTS:-https://sentinel-rpc.polkachu.com:443,https://sentinel-rpc.publicnode.com:443}"
LCD="${LCD_ENDPOINT:-https://lcd.sentinel.co}"

ADDRESS=$(cat "${WORK_DIR}/.address" 2>/dev/null | cut -d '"' -f2 | xargs)

if [ -z "$ADDRESS" ]; then
  echo "❌ No address found (${WORK_DIR}/.address is empty or missing)"
  exit 1
fi

echo "=== Sentinel Stale Sessions & Balance ==="

bash "$(dirname "$0")/sentinel-balance.sh" | grep DVPN
echo "→ Full balance & history: https://p2pscan.com/address/$ADDRESS"

echo ""


echo -e "\n=== Time until refunds ===\n"

sentinel-dvpncli query sessions \
  --account-addr "$ADDRESS" \
  --rpc.addrs "$RPC" 2>/dev/null | \
awk '
  /id:/ {id=$NF}
  /inactive_at:/ {
    gsub(/"/,"",$NF);
    timestamp = $NF;
    cmd="date -d \"" timestamp "\" +\"%H:%M:%S\""; cmd | getline nice_time; close(cmd);
    cmd2="date -d \"" timestamp "\" +%s"; cmd2 | getline expire; close(cmd2);
    now = systime();
    left = expire - now;
    if (left > 0) {
      m = int(left/60);
      printf "Session %-12s → expires at %s   (%d min left)\n", id, nice_time, m
    } else {
      printf "Session %-12s → %s   ✅ Expired\n", id, nice_time
    }
  }
'

echo -e "\n=== Summary ==="
echo "• Tokens locked in inactive_pending sessions"
echo "• Deposits return automatically when timers hit 0"
echo "• Refresh p2pscan after sessions disappear from the list"