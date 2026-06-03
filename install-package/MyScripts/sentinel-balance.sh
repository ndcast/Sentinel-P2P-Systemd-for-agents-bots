#!/bin/bash
# Sentinel Balance — LCD API

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../sentinel-env.sh" ]]; then
  source "${SCRIPT_DIR}/../sentinel-env.sh"
elif [[ -f "${HOME}/sentinel-dvpncli/sentinel-env.sh" ]]; then
  source "${HOME}/sentinel-dvpncli/sentinel-env.sh"
fi

WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
LCD="${LCD_ENDPOINT:-https://lcd.sentinel.co}"

ADDRESS=$(cat "${WORK_DIR}/.address" 2>/dev/null | cut -d '"' -f2 | xargs)

if [ -z "$ADDRESS" ]; then
  echo "❌ No address found (${WORK_DIR}/.address is empty or missing)"
  exit 1
fi

echo "=== Fetching real balance via LCD API ==="

curl -s -X GET \
  -H "Content-Type: application/json" \
  "${LCD}/cosmos/bank/v1beta1/balances/${ADDRESS}" | \
jq -r '.balances[]? | select(.denom == "udvpn") | "\(.amount) udvpn = \(.amount | tonumber / 1000000) DVPN"' || \
echo "No udvpn balance found or API error"

echo -e "\n→ Explorer: https://p2pscan.com/address/$ADDRESS"