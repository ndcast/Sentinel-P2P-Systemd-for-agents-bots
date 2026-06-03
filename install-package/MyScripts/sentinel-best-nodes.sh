#!/bin/bash
# sentinel-best-nodes.sh — list top NL/DE/FR nodes (no plan filter — pay per GB)

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

echo "=== Top Nodes (${COUNTRY_CODES//|/\\/}) ==="
echo "(No plan filter — all shown, pay per GB)"
echo "Blacklisted nodes excluded."
echo ""

# get_filtered_nodes returns: DOWNLINK|ADDR|COUNTRY sorted desc
# Pipe through awk for formatted output
get_filtered_nodes 500 | awk -F'|' '{
  printf "Node    : %s\n", $2
  printf "Country : %s\n", $3
  printf "Downlink: %s bytes/s\n", $1
  printf "----------------------------------\n"
}'

echo ""
echo "To connect to a node: bash sentinel-select-best-node.sh"
echo "Or override countries: bash $0 -C NL,MX,DE"