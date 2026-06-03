#!/bin/bash
echo "=== Sentinel dVPN Prerequisites Installer ==="

echo "[+] Updating system..."
sudo apt update

echo "[+] Installing base tools (expect, curl, jq)..."
sudo apt install -y expect curl jq

echo "[+] Checking Go version..."
GO_VERSION=$(go version 2>/dev/null | grep -oP 'go\d+\.\d+' | tr -d 'go')
REQUIRED_MAJOR=1
REQUIRED_MINOR=24
if [[ -n "$GO_VERSION" ]]; then
  MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
  MINOR=$(echo "$GO_VERSION" | cut -d. -f2)
  if [[ "$MAJOR" -lt "$REQUIRED_MAJOR" || ( "$MAJOR" -eq "$REQUIRED_MAJOR" && "$MINOR" -lt "$REQUIRED_MINOR" ) ]]; then
    echo "   Go version too old ($GO_VERSION) — upgrading to 1.24.6..."
    curl -fsSL https://go.dev/dl/go1.24.6.linux-amd64.tar.gz -o /tmp/go1.24.6.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go1.24.6.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
    sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
    rm /tmp/go1.24.6.tar.gz
    export PATH=/usr/local/go/bin:$PATH
    echo "   Go upgraded."
  else
    echo "   Go $GO_VERSION OK"
  fi
else
  echo "   Go not found — installing 1.24.6..."
  curl -fsSL https://go.dev/dl/go1.24.6.linux-amd64.tar.gz -o /tmp/go1.24.6.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf /tmp/go1.24.6.tar.gz
  sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
  sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm /tmp/go1.24.6.tar.gz
  export PATH=/usr/local/go/bin:$PATH
fi

echo "[+] Installing WireGuard..."
sudo apt install -y wireguard-tools wireguard resolvconf iptables

echo "[+] Installing/Updating Xray..."

XRAY_VERSION=""
if command -v xray &> /dev/null; then
    XRAY_VERSION=$(xray version 2>/dev/null | head -1 | awk '{print $2}')
    echo "   Current Xray version: $XRAY_VERSION"
fi

if [[ -z "$XRAY_VERSION" ]]; then
    echo "   Xray not found — installing latest..."
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
else
    echo "   Checking for Xray updates..."
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
fi

# Verify installation
if command -v xray &> /dev/null; then
    echo "   Xray installed: $(xray version 2>/dev/null | head -1)"
else
    echo "   Warning: Xray installation may have failed. Falling back to apt v2ray..."
    sudo apt install -y v2ray || echo "   Could not install v2ray either."
fi

echo "[+] Loading WireGuard kernel module..."
sudo modprobe wireguard
echo "wireguard" | sudo tee /etc/modules-load.d/wireguard.conf >/dev/null

echo "[+] Configuring DNS..."
sudo systemctl stop resolvconf 2>/dev/null || true
sudo tee /etc/resolvconf/resolv.conf.d/head > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
sudo resolvconf -u 2>/dev/null || true
sudo systemctl start resolvconf systemd-resolved 2>/dev/null || true

echo "[+] Verifying installations..."
echo "   Go:        $(go version 2>/dev/null | grep -oP 'go[\d.]+')"
echo "   WireGuard: $(which wg-quick && wg-quick --version 2>/dev/null | head -1)"
echo "   Xray:      $(which xray && xray version 2>/dev/null | head -1)"
echo "   Expect:    $(which expect)"
echo "   curl:      $(curl --version | head -1)"
echo "   jq:        $(jq --version 2>/dev/null)"
echo "   DNS:       $(cat /etc/resolv.conf | head -3)"
echo "   RPC test:  $(nslookup sentinel-rpc.polkachu.com 2>/dev/null | grep -m1 'Address:' | awk '{print $2}')"

echo ""
echo "=== Done ==="
echo "Next: bash sentinel-connect.sh"