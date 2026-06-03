#!/bin/bash
# sentinel-node-lib-v2.sh — shared node-filtering logic (with protocol support)
# Source this from sentinel-auto-nodes.sh, sentinel-best-nodes.sh, sentinel-select-best-node.sh

# -----------------------------
# Environment
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

COUNTRY_CODES=""

node_lib_load_countries() {
  if [[ -n "$COUNTRY_CODES" ]]; then return 0; fi
  if [[ -f "${WORK_DIR}/.country_filter" ]]; then
    local raw
    raw=$(grep -v '^#' "${WORK_DIR}/.country_filter" | grep -v '^$' | tr '\n' '|' | sed 's/|$//')
    if [[ -n "$raw" ]]; then
      COUNTRY_CODES="$raw"
      return 0
    fi
  fi
  COUNTRY_CODES="${COUNTRY_FILTER:-NL|DE|FR}"
}

is_blacklisted() {
  local addr="$1"
  if [[ -z "$addr" ]] || [[ ! -f "$BLACKLIST_FILE" ]]; then
    return 1
  fi
  grep -qE "^${addr}$" "$BLACKLIST_FILE" 2>/dev/null
}

# -----------------------------
# get_filtered_nodes v2 — now supports protocol filter
# Default protocol = "wireguard" (change to "all" to get everything)
# Uses service_type (not protocol) based on actual CLI output
# -----------------------------
get_filtered_nodes() {
  local page_limit="${1:-500}"
  local protocol_filter="${2:-wireguard}"   # default = wireguard
  local raw

  raw=$(sentinel-dvpncli query nodes \
    --status active \
    --page.limit "$page_limit" \
    --rpc.addrs "$RPC" 2>/dev/null)

  if [[ -z "$raw" ]]; then
    echo "ERROR: failed to fetch nodes from RPC" >&2
    return 1
  fi

  echo "$raw" | awk -v codes="$COUNTRY_CODES" -v bl="$BLACKLIST_FILE" -v proto="$protocol_filter" '
    BEGIN {
      if (bl != "") {
        while ((getline line < bl) > 0) {
          if (line ~ /^#/ || line == "") continue
          blacklist[line] = 1
        }
        close(bl)
      }
      n = split(codes, arr, "|")
      want_all = (proto == "all" || proto == "")
    }
    /address: sentnode/ { addr = $2 }
    /country_code: / {
      country = $2
      good = 0
      for (i = 1; i <= n; i++) {
        if (country == arr[i]) { good = 1; break }
      }
    }
    /service_type: / {
      node_proto = $2
    }
    /downlink: / {
      dl = $2 + 0
      if (addr && good && !(addr in blacklist)) {
        if (want_all || node_proto == proto) {
          print dl "|" addr "|" country
        }
        addr = ""; good = 0; node_proto = ""
      } else {
        addr = ""; good = 0; node_proto = ""
      }
    }
  ' | sort -t'|' -nr
}
