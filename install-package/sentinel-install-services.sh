#!/bin/bash
set -euo pipefail

echo "=== Sentinel dVPN — Service Installer ==="

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
 echo "Error: Run as root or with sudo"
 exit 1
fi

# Determine script directory (resolve symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use SUDO_USER if set, otherwise logname (works in non-interactive sudo shells), fallback to whoami
RUNAS="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
HOMEDIR=$(getent passwd "$RUNAS" 2>/dev/null | cut -d: -f6)
MY_SCRIPTS_DIR="${HOMEDIR}/sentinel-dvpncli/MyScripts"

# Service files to install
SERVICES=(
 "sentinel-dvpn.service"
 "sentinel-favs-dvpn.service"
 "sentinel-wg-monitord.service"
)

echo "[+] Copying service files to /etc/systemd/system/ ..."

for svc in "${SERVICES[@]}"; do
 src="${SCRIPT_DIR}/ServiceFiles/${svc}"
 dst="/etc/systemd/system/${svc}"

 if [[ ! -f "$src" ]]; then
  echo "Error: $src not found"
  exit 1
 fi

 echo "  Installing $svc ..."
 sed "s/__RUNAS__/$RUNAS/g; s|__HOMEDIR__|$HOMEDIR|g; s|__SCRIPTDIR__|$MY_SCRIPTS_DIR|g" "$src" > "$dst"
 chmod 644 "$dst"
done

echo "[+] Reloading systemd daemon ..."
systemctl daemon-reload

echo ""
echo "=== Installation complete ==="
echo ""
echo "Available services:"
echo "  sentinel-dvpn.service      — auto-connect (random/fallback node)"
echo "  sentinel-favs-dvpn.service — auto-connect with favorite providers"
echo "  sentinel-wg-monitord.service — WG state monitor daemon"
echo ""
echo "To enable and start:"
echo "  sudo systemctl enable sentinel-dvpn.service"
echo "  sudo systemctl start  sentinel-dvpn.service"
echo ""
echo "To start the favs variant instead:"
echo "  sudo systemctl enable sentinel-favs-dvpn.service"
echo "  sudo systemctl start  sentinel-favs-dvpn.service"
echo ""
echo "To check status:"
echo "  sudo systemctl status sentinel-dvpn.service"
echo "  journalctl -u sentinel-dvpn.service -f"