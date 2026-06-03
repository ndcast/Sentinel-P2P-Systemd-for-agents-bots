#!/bin/bash
# sentinel-ip-vpnbypass.sh — Anti-lockout (ip rule) + Additive WireGuard AllowedIPs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHITELIST="${SCRIPT_DIR}/../whitelist-gws.lst"
WG_IF="wg0"

# Get priority of the 'suppress_prefixlength 0' rule and set ours 10 lower
SUPPRESS_PRIORITY=$(sudo ip rule show | grep prefixlength | cut -d":" -f1 | xargs)
if [ -z "$SUPPRESS_PRIORITY" ]; then
    echo "[$(date '+%H:%M:%S')] SUPPRESS_PRIORITY is null - skipping anti-lockout"
    exit 0
fi

PRIORITY=$((SUPPRESS_PRIORITY - 10))

echo "[$(date '+%H:%M:%S')] Starting anti-lockout + AllowedIPs protection..."

# ============================================
# 1. ip rule anti-lockout (protect SSH + server)
# ============================================

# Clean any existing rules at this priority first
sudo ip rule del priority "$PRIORITY" 2>/dev/null || true

declare -A PROTECTED_IPS=()

add_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && [[ -z "${PROTECTED_IPS[$ip]:-}" ]]; then
        PROTECTED_IPS[$ip]=1
    fi
}

# Load IPs from whitelist-gws.lst
if [ -f "$WHITELIST" ]; then
    echo "Loading IPs from whitelist-gws.lst..."
    while IFS= read -r line || [[ -n "$line" ]]; do
        ip=$(echo "$line" | sed 's/#.*//' | tr -d '[:space:]')
        [[ -n "$ip" ]] && add_ip "$ip"
    done < "$WHITELIST"
fi

# Detect current SSH source IPs
echo "Detecting active SSH connections..."
mapfile -t SSH_SRC < <(ss -Htn state established '( sport = :22 )' 2>/dev/null \
    | awk '{print $5}' \
    | cut -d: -f1 \
    | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$')

for ip in "${SSH_SRC[@]}"; do
    add_ip "$ip"
done

# Fallback to primary interface IP
if [ ${#PROTECTED_IPS[@]} -eq 0 ]; then
    LOCAL_IP=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -n1)
    [[ -n "$LOCAL_IP" ]] && add_ip "$LOCAL_IP"
fi

# Proactive cleanup: remove all stale from/to rules for protected IPs
# (prevents accumulation of old priorities like 18/30/40/50 across WG restarts)
for ip in "${!PROTECTED_IPS[@]}"; do
    while read x; do
        sudo ip rule del priority $x;done < <(sudo ip rule show | grep $ip | cut -d":" -f1)
done

# Apply ip rules
echo ""
echo "Applying anti-lockout rules (priority $PRIORITY)..."
for ip in "${!PROTECTED_IPS[@]}"; do
    sudo ip rule add from "$ip" lookup main priority "$PRIORITY" 2>&1 || true
    sudo ip rule add to "$ip" lookup main priority "$PRIORITY" 2>&1 || true
    echo "  + Protected (ip rule): $ip"
done

# Update whitelist file cleanly
if [ ${#PROTECTED_IPS[@]} -gt 0 ]; then
    for ip in "${!PROTECTED_IPS[@]}"; do
        grep -q "^${ip}$" "$WHITELIST" 2>/dev/null || echo "$ip" >> "$WHITELIST"
    done
fi

echo "=== Active anti-lockout rules ==="
sudo ip rule show | grep "^$PRIORITY:" || echo "No rules at priority $PRIORITY"

# ============================================
# 2. Additive WireGuard AllowedIPs
# ============================================

if ip link show "$WG_IF" &>/dev/null; then
    echo ""
    echo "Updating WireGuard AllowedIPs (additive)..."

    # Read current AllowedIPs
    CURRENT_ALLOWED=$(wg show "$WG_IF" allowed-ips 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

    # Read IPs from whitelist
    WG_IPS=()
    if [ -f "$WHITELIST" ]; then
        mapfile -t WG_IPS < <(grep -vE '^\s*#|^\s*$' "$WHITELIST" | tr -d '[:space:]')
    fi

    # Merge (deduplicate)
    declare -A ALL_IPS=()
    IFS=',' read -ra CURR <<< "$CURRENT_ALLOWED"
    for ip in "${CURR[@]}"; do
        [[ -n "$ip" ]] && ALL_IPS["$ip"]=1
    done
    for ip in "${WG_IPS[@]}"; do
        [[ -n "$ip" ]] && ALL_IPS["$ip"]=1
    done

    # Build final list
    FINAL_LIST=$(printf "%s," "${!ALL_IPS[@]}" | sed 's/,$//')

    if [ -n "$FINAL_LIST" ]; then
        if wg set "$WG_IF" allowed-ips "$FINAL_LIST" 2>/dev/null; then
            echo "  + AllowedIPs updated on $WG_IF (additive)"
        else
            echo "  ! Failed to update AllowedIPs on $WG_IF"
        fi
    fi
else
    echo ""
    echo "WireGuard interface $WG_IF not found — skipping AllowedIPs update."
fi

echo ""
echo "[$(date '+%H:%M:%S')] Protection complete (${#PROTECTED_IPS[@]} IPs protected)."

