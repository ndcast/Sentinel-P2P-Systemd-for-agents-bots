#!/bin/bash
# sentinel-auto-nodes.sh — auto-select top-5 nodes by downlink speed

# Load shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/sentinel-node-lib.sh"

# Parse own args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C|--countries)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: -C requires a country list argument" >&2
        exit 1
      fi
      local raw="$2"
      IFS=',' read -ra COUNTRY_CODES_ARRAY <<< "$raw"
      COUNTRY_CODES=$(IFS='|'; echo "${COUNTRY_CODES_ARRAY[*]}")
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-C CN1,CN2,CN3]"
      echo "  -C  Override country filter (default: NL,DE,FR or .country_filter)"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Load countries from file/default if not set via -C
node_lib_load_countries

echo "=== Auto Selecting Top 5 Best Nodes (${COUNTRY_CODES//|/\\/}) ==="
echo "Sorting by: downlink speed"
echo "(Blacklisted nodes excluded)"
echo ""

# get_filtered_nodes returns: DOWNLINK|ADDR|COUNTRY
# We need more detail than that, so fetch raw and filter in awk
# (keep the rich output from the original script)
WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
RPC="${RPC_ENDPOINTS:-https://sentinel-rpc.polkachu.com:443,https://sentinel-rpc.publicnode.com:443}"

sentinel-dvpncli query nodes \
  --status active \
  --page.limit 500 \
  --rpc.addrs "$RPC" 2>/dev/null | \
awk -v codes="$COUNTRY_CODES" -v bl="${WORK_DIR}/blacklist-nodes.lst" '
BEGIN {
  n = split(codes, arr, "|")
  if (bl != "") {
    while ((getline line < bl) > 0) {
      if (line ~ /^#/ || line == "") continue
      blacklist[line] = 1
    }
    close(bl)
  }
}
/address: sentnode/ { addr = $2 }
/country_code: / {
  country = $2
  good = 0
  for (i = 1; i <= n; i++) {
    if (country == arr[i]) { good = 1; break }
  }
}
/city:/ { city = $2 }
/moniker:/ { moniker = $2 }
/peers:/ { peers = $2 }
/service_type:/ { service = $2 }
/downlink: / {
  dl = $2 + 0
  if (good && addr != "" && !(addr in blacklist)) {
    print dl "|" addr "|" country "|" city "|" moniker "|" peers "|" service
    good = 0
  } else {
    addr = ""; good = 0
  }
}
' | sort -n -r | head -n 5 | \
awk -F'|' '{
  printf "Rank #%d\n", NR
  printf "Node    : %s\n", $2
  printf "Country : %s\n", $3
  printf "City    : %s\n", $4
  printf "Moniker : %s\n", $5
  printf "Peers   : %s\n", $6
  printf "Type    : %s\n", $7
  printf "Downlink: %s bytes/s\n", $1
  printf "----------------------------------\n"
}'