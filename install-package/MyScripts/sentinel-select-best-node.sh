#!/bin/bash
# sentinel-select-best-node.sh — pick one random node from TOP 10 by downlink

# Load shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/sentinel-node-lib.sh"

# Defaults
WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
BEST_FILE="${HOME}/.best-sentinel-node"

# Parse own args FIRST (sets COUNTRY_CODES if -C given)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C|--countries)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: -C requires a country list argument" >&2
        exit 1
      fi
      raw="$2"
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

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Selecting Best Node (${COUNTRY_CODES//|/\\/}) ==="

# Get filtered+sorted nodes (uses get_filtered_nodes which already skips blacklisted)
TOP_NODES=$(get_filtered_nodes 500 | head -10)

if [[ -z "$TOP_NODES" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ No active nodes found (check country filter / blacklist)"
  exit 1
fi

# Count lines (there may be fewer than 10 if filter is narrow)
COUNT=$(echo "$TOP_NODES" | wc -l)
if [[ "$COUNT" -eq 1 ]]; then
  BEST_NODE=$(echo "$TOP_NODES" | cut -d'|' -f2)
  COUNTRY=$(echo "$TOP_NODES" | cut -d'|' -f3)
else
  # Pick one at random from the top 10
  BEST_LINE=$(echo "$TOP_NODES" | shuf -n1)
  BEST_NODE=$(echo "$BEST_LINE" | cut -d'|' -f2)
  COUNTRY=$(echo "$BEST_LINE" | cut -d'|' -f3)
fi

if [[ -n "$BEST_NODE" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Selected node: $BEST_NODE ($COUNTRY)"
  echo "$BEST_NODE" > "$BEST_FILE"
  exit 0
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Selection failed"
  exit 1
fi