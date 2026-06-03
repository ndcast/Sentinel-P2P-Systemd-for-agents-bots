#!/bin/bash
# sentinel-node-lib.sh — shared node-filtering logic
# Source this from sentinel-auto-nodes.sh, sentinel-best-nodes.sh, sentinel-select-best-node.sh
# Provides: country code parsing, blacklist check, filtered node fetching

# -----------------------------
# Environment (same pattern as all other scripts)
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../sentinel-env.sh" ]]; then
  source "${SCRIPT_DIR}/../sentinel-env.sh"
elif [[ -f "${HOME}/sentinel-dvpncli/sentinel-env.sh" ]]; then
  source "${HOME}/sentinel-dvpncli/sentinel-env.sh"
fi

WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
RPC="${RPC_ENDPOINTS:-https://sentinel-rpc.polkachu.com:443,https://sentinel-rpc.publicnode.com:443}"
BLACKLIST_FILE="${WORK_DIR}/blacklist-nodes.lst"

# -----------------------------
# Country codes — CLI override (-C CN1,CN2,CN3) or file or default
# Call node_lib_parse_args "$@" BEFORE using COUNTRY_CODES
# -----------------------------
COUNTRY_CODES=""   # set by node_lib_parse_args or node_lib_load_countries

# Parse -C <CN1,CN2,CN3> from script's own "$@"
# Call this in your script's argument-parsing section, then call node_lib_load_countries
node_lib_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -C|--countries)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: -C requires a country list argument" >&2
          return 1
        fi
        # Support both comma-separated (-C NL,DE,FR) and repeated (-C NL -C DE -C FR)
        local raw="$2"
        # If the value itself contains commas, split on commas; otherwise treat as single code
        IFS=',' read -ra COUNTRY_CODES_ARRAY <<< "$raw"
        # Build pipe-delimited string
        COUNTRY_CODES=$(IFS='|'; echo "${COUNTRY_CODES_ARRAY[*]}")
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
}

# Load country codes from file or env default (called if -C was not given)
node_lib_load_countries() {
  if [[ -n "$COUNTRY_CODES" ]]; then return 0; fi  # already set via -C
  if [[ -f "${WORK_DIR}/.country_filter" ]]; then
    # Support multi-line file, ignore blank lines and comments
    local raw
    raw=$(grep -v '^#' "${WORK_DIR}/.country_filter" | grep -v '^$' | tr '\n' '|' | sed 's/|$//')
    if [[ -n "$raw" ]]; then
      COUNTRY_CODES="$raw"
      return 0
    fi
  fi
  # Final fallback
  COUNTRY_CODES="${COUNTRY_FILTER:-NL|DE|FR}"
}

# -----------------------------
# Blacklist check
# Returns 0 (true) if addr is in blacklist, 1 (false) if not
# Usage: if is_blacklisted "$ADDR"; then ... fi
# -----------------------------
is_blacklisted() {
  local addr="$1"
  if [[ -z "$addr" ]] || [[ ! -f "$BLACKLIST_FILE" ]]; then
    return 1
  fi
  # Exact match only — anchors prevent partial matches
  grep -qE "^${addr}$" "$BLACKLIST_FILE" 2>/dev/null
}

# -----------------------------
# Add a node to the blacklist with timestamp and reason
# Usage: blacklist_add "$ADDR" "provider fault: WG tunnel died post-connect"
# -----------------------------
blacklisted_add() {
  local addr="$1"
  local reason="${2:-unknown}"
  if [[ -z "$addr" ]]; then return 1; fi
  mkdir -p "$(dirname "$BLACKLIST_FILE")"
  touch "$BLACKLIST_FILE"
  # Deduplicate — remove existing entry for this addr first
  local tmp
  tmp=$(mktemp)
  grep -vE "^${addr}$" "$BLACKLIST_FILE" > "$tmp"
  echo "# $(date '+%Y-%m-%d %H:%M:%S') — $reason" >> "$tmp"
  echo "$addr" >> "$tmp"
  mv "$tmp" "$BLACKLIST_FILE"
  chmod 600 "$BLACKLIST_FILE"
}

# -----------------------------
# Fetch and filter nodes from the blockchain
# Returns lines: DOWNLINK|ADDR|COUNTRY
# The caller handles output formatting and selection
# Usage: while IFS='|' read -r dl addr country; do ...; done < <(get_filtered_nodes)
# -----------------------------
get_filtered_nodes() {
  local page_limit="${1:-500}"
  local verbose="${2:-}"
  local raw

  # Fetch raw node data
  raw=$(sentinel-dvpncli query nodes \
    --status active \
    --page.limit "$page_limit" \
    --rpc.addrs "$RPC" 2>/dev/null)

  if [[ -z "$raw" ]]; then
    echo "ERROR: failed to fetch nodes from RPC" >&2
    return 1
  fi

  # Parse: awk sees each node block (~15-20 lines), extracts key fields,
  # skips blacklist entries, outputs DOWNLINK|ADDR|COUNTRY sorted desc by downlink
  echo "$raw" | awk -v codes="$COUNTRY_CODES" -v bl="$BLACKLIST_FILE" '
    BEGIN {
      # Load blacklist into an associative array for fast lookup
      if (bl != "") {
        while ((getline line < bl) > 0) {
          # Skip blank lines and comments
          if (line ~ /^#/ || line == "") continue
          blacklist[line] = 1
        }
        close(bl)
      }
      n = split(codes, arr, "|")
    }
    /address: sentnode/ { addr = $2 }
    /country_code: / {
      country = $2
      good = 0
      for (i = 1; i <= n; i++) {
        if (country == arr[i]) { good = 1; break }
      }
    }
    /downlink: / {
      dl = $2 + 0
      if (addr && good && !(addr in blacklist)) {
        print dl "|" addr "|" country
        addr = ""; good = 0
      } else {
        addr = ""; good = 0
      }
    }
  ' | sort -t'|' -nr
}