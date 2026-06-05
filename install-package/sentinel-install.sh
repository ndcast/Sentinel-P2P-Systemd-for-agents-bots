#!/bin/bash
# Sentinel dVPN — Full Automated Installer
# Usage: bash sentinel-install.sh -p passphrase
#   or:  bash sentinel-install.sh           (interactive)

set -euo pipefail

CURRENT_HOME="$HOME"
export CURRENT_HOME

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${CURRENT_HOME}/sentinel-dvpncli"
BINARY_OK=false
PASSPHRASE=""

# ====================
# Argument Parsing
# ====================
while getopts "p:h" opt; do
  case $opt in
    p) PASSPHRASE="$OPTARG" ;;
    h) echo "Usage: $0 [-p passphrase]"
       echo "       $0              (interactive)"
       exit 0 ;;
  esac
done

# ====================
# Step 1: Passphrase
# ====================
echo -e "${GREEN}=== Sentinel dVPN Installer ===${NC}"
echo ""

if [[ -z "$PASSPHRASE" ]]; then
  echo -e "${YELLOW}Step 1/8 — Wallet Passphrase${NC}"
  read -r -p "Enter keyring passphrase (min 4 chars): " PASSPHRASE
  if [[ ${#PASSPHRASE} -lt 4 ]]; then
    echo -e "${RED}Error: passphrase must be at least 4 characters${NC}"
    exit 1
  fi

  read -r -p "Confirm passphrase: " PASSPHRASE2
  if [[ "$PASSPHRASE" != "$PASSPHRASE2" ]]; then
    echo -e "${RED}Error: passphrases do not match${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}Step 1/8 — Wallet Passphrase${NC}"
  if [[ ${#PASSPHRASE} -lt 4 ]]; then
    echo -e "${RED}Error: passphrase must be at least 4 characters${NC}"
    exit 1
  fi
fi

echo -e "${GREEN}   Passphrase set${NC}"
echo ""

# ====================
# Step 2: Clone Repo
# ====================
echo -e "${YELLOW}Step 2/8 — Cloning Repository${NC}"

if [[ -d "$WORK_DIR" ]]; then
  echo "   Removing previous installation..."
  rm -rf "$WORK_DIR"
fi

echo "   Cloning sentinel-dvpncli..."
git clone https://github.com/sentinel-official/sentinel-dvpncli.git "$WORK_DIR" 2>&1 | tail -3
echo -e "${GREEN}   Done${NC}"
echo ""

# ====================
# Step 3: Copy Config Files
# ====================
echo -e "${YELLOW}Step 3/8 — Copying Config Files${NC}"

# Copy from canonicals if available
if [[ -d "$SCRIPT_DIR" ]]; then
  [[ -f "$SCRIPT_DIR/.env" ]] && cp "$SCRIPT_DIR/.env" "$WORK_DIR/.env"
  [[ -f "$SCRIPT_DIR/sentinel-env.sh" ]] && cp "$SCRIPT_DIR/sentinel-env.sh" "$WORK_DIR/sentinel-env.sh"
  [[ -f "$SCRIPT_DIR/.country_filter" ]] && cp "$SCRIPT_DIR/.country_filter" "$WORK_DIR/.country_filter" 2>/dev/null || true
fi

# Create .passphrase
echo "$PASSPHRASE" > "$WORK_DIR/.passphrase"
chmod 600 "$WORK_DIR/.passphrase"

# Copy MyScripts
mkdir -p "$WORK_DIR/MyScripts"
if [[ -d "$SCRIPT_DIR/MyScripts" ]]; then
  for script in "$SCRIPT_DIR/MyScripts"/*.sh; do
    [[ -f "$script" ]] && cp "$script" "$WORK_DIR/MyScripts/"
  done
fi
if [[ -f "$SCRIPT_DIR/dvpn-key-import.exp" ]]; then
  cp "$SCRIPT_DIR/dvpn-key-import.exp" "$WORK_DIR/"
fi

chmod +x "$WORK_DIR"/MyScripts/*.sh 2>/dev/null || true
chmod +x "$WORK_DIR/sentinel-env.sh" 2>/dev/null || true
chmod +x "$WORK_DIR/dvpn-key-import.exp" 2>/dev/null || true

echo -e "${GREEN}   Config files ready${NC}"
echo ""

# ====================
# Step 4: Install Prerequisites + Go + WireGuard + DNS
# ====================
echo -e "${YELLOW}Step 4/8 — Installing Prerequisites${NC}"

export PATH=/usr/local/go/bin:$PATH
bash "$WORK_DIR/MyScripts/sentinel-install-prereq-tools.sh"

echo "   Creating script symlinks in \$HOME..."
# Symlinks so systemd services can find scripts at /home/
ln -sf "$WORK_DIR/MyScripts/sentinel-connect.sh" "${CURRENT_HOME}/sentinel-connect.sh"
ln -sf "$WORK_DIR/MyScripts/sentinel-select-best-node.sh" "${CURRENT_HOME}/sentinel-select-best-node.sh"
ln -sf "$WORK_DIR/MyScripts/sentinel-best-nodes.sh" "${CURRENT_HOME}/sentinel-best-nodes.sh"
ln -sf "$WORK_DIR/MyScripts/sentinel-balance.sh" "${CURRENT_HOME}/sentinel-balance.sh"
ln -sf "$WORK_DIR/sentinel-env.sh" "${CURRENT_HOME}/sentinel-env-helper.sh" 2>/dev/null || true
ln -sf "$WORK_DIR/MyScripts/sentinel-countdown.sh" "${CURRENT_HOME}/sentinel-countdown.sh"
ln -sf "$WORK_DIR/MyScripts/sentinel-ip-vpnbypass.sh" "${CURRENT_HOME}/sentinel-ip-vpnbypass.sh"
ln -sf "$WORK_DIR/fav-providers.lst" "${CURRENT_HOME}/fav-providers.lst"
ln -sf "$WORK_DIR/MyScripts/sentinel-disconnect.sh" "${CURRENT_HOME}/sentinel-disconnect.sh"

echo "   Symlinks created ✅"
echo ""

# ====================
# Step 5: Build Binary
# ====================
echo -e "${YELLOW}Step 5/8 — Building Binary${NC}"

export PATH=/usr/local/go/bin:$PATH
echo "   Go version: $(go version | grep -oP 'go[\d.]+')"

echo "   Building sentinel-dvpncli..."
cd "$WORK_DIR"
GOGC=50 go install -ldflags='-s -w -X github.com/sentinel-official/sentinel-go-sdk/version.Commit=4463e4caeb03b5ae6ad798075bec7eaff1bd77b9 -X github.com/sentinel-official/sentinel-go-sdk/version.Tag=4.0.0-59-g4463e4c' -tags=netgo . 2>&1 | tail -5

if [[ -f "${CURRENT_HOME}/go/bin/sentinel-dvpncli" ]]; then
  sudo ln -sf "${CURRENT_HOME}/go/bin/sentinel-dvpncli" /usr/local/bin/sentinel-dvpncli
  BINARY_OK=true
  echo -e "${GREEN}   Binary built and installed${NC}"
else
  echo -e "${RED}   Binary build failed${NC}"
  exit 1
fi
echo ""

# ====================
# Step 6: Install Systemd Services
# ====================
echo -e "${YELLOW}Step 6/8 — Installing Systemd Services${NC}"

cd "$SCRIPT_DIR"
sudo bash sentinel-install-services.sh

sudo systemctl daemon-reload
echo -e "${GREEN}   Systemd services ready${NC}"
echo ""

# ====================
# Step 6.5: Copy critical config files to WORK_DIR
# ====================
echo -e "${YELLOW}Step 6.5/8 — Copying config files to WORK_DIR${NC}"

sudo cp "$SCRIPT_DIR/fav-providers.lst" "$WORK_DIR/"
sudo cp "$SCRIPT_DIR/whitelist-gws.lst" "$WORK_DIR/"

echo -e "${GREEN}   Config files copied${NC}"
echo ""

# ====================
# Step 6.6: Detect current SSH IP (port 22) and replace whitelist-gws.lst template content
# ====================
echo -e "${YELLOW}Step 6.6/8 — Detecting current SSH IP for whitelist${NC}"

WHITELIST_FILE="$WORK_DIR/whitelist-gws.lst"
declare -A CURRENT_IPS=()

# Detect current SSH source IPs on port 22 (same logic as sentinel-ip-vpnbypass.sh)
mapfile -t SSH_SRC < <(ss -Htn state established '( sport = :22 )' 2>/dev/null \
    | awk '{print $5}' \
    | cut -d: -f1 \
    | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$')

for ip in "${SSH_SRC[@]}"; do
    CURRENT_IPS["$ip"]=1
done

# Fallback to primary interface IP if nothing detected
if [ ${#CURRENT_IPS[@]} -eq 0 ]; then
    LOCAL_IP=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -n1)
    [[ -n "$LOCAL_IP" ]] && CURRENT_IPS["$LOCAL_IP"]=1
fi

# Replace entire whitelist content (remove any template)
if [ ${#CURRENT_IPS[@]} -gt 0 ]; then
    : > "$WHITELIST_FILE"
    for ip in "${!CURRENT_IPS[@]}"; do
        echo "$ip" >> "$WHITELIST_FILE"
    done
    echo -e "${GREEN}   whitelist-gws.lst updated with current SSH IP(s) — template content replaced${NC}"
else
    echo -e "${YELLOW}   No SSH IP detected — keeping existing whitelist${NC}"
fi
echo ""

# ====================
# Step 7: Create Wallet + Import into Test Keyring
# ====================
echo -e "${YELLOW}Step 7/8 — Creating Wallet${NC}"

export PATH=/usr/local/go/bin:$PATH

# Use expect with empty mnemonic (binary auto-generates)
cat > "${WORK_DIR}/sentinel-key.exp" << 'ENDOFFILE'
set timeout 60
spawn sentinel-dvpncli keys add main --keyring.backend test --home "$env(CURRENT_HOME)/sentinel-dvpncli"
expect {
  "Enter your BIP-39 mnemonic" { send "\r" }
  timeout { exit 1 }
}
expect {
  "Enter your BIP-39 passphrase" { send "\r" }
  timeout { exit 1 }
}
expect {
  "Enter keyring passphrase" { send "$env(PASSPHRASE)\r" }
  timeout { exit 1 }
}
expect {
  "Enter keyring passphrase again:" { send "$env(PASSPHRASE)\r" }
  timeout { exit 1 }
}
expect eof
ENDOFFILE

PASSPHRASE="$PASSPHRASE" expect "${WORK_DIR}/sentinel-key.exp" > "${WORK_DIR}/sentinel-key.out" 2>&1 || true
cat "${WORK_DIR}/sentinel-key.out"

# Extract address and mnemonic from output
ADDRESS=$(grep -oE 'address: sent1[a-z0-9]+' "${WORK_DIR}/sentinel-key.out" | awk '{print $2}' | head -1)
MNEMONIC=$(grep -oE '([a-z]+[[:space:]]+){23}[a-z]+' "${WORK_DIR}/sentinel-key.out" | tail -1 | xargs)

if [[ -z "$ADDRESS" ]]; then
  echo -e "${RED}   Wallet creation failed — address not found${NC}"
  exit 1
fi

echo "ADDRESS=\"$ADDRESS\"" > "$WORK_DIR/.address"
chmod 600 "$WORK_DIR/.address"

if [[ $(wc -w <<< "$MNEMONIC") -eq 24 ]]; then
  echo "$MNEMONIC" > "$WORK_DIR/.mnemonic"
  chmod 600 "$WORK_DIR/.mnemonic"
  echo -e "${GREEN}   Wallet created${NC}"
else
  echo -e "${YELLOW}   Wallet created (mnemonic capture failed — save manually from output above)${NC}"
fi

# Import into test keyring (for systemd non-interactive use)
echo "   Importing mnemonic into test keyring..."
if [[ -f "$WORK_DIR/dvpn-key-import.exp" ]]; then
  expect "$WORK_DIR/dvpn-key-import.exp" > "${WORK_DIR}/key-import.out" 2>&1 || true
  if grep -q "address:" "${WORK_DIR}/key-import.out" 2>/dev/null; then
    echo -e "${GREEN}   Test keyring import OK${NC}"
  else
    echo -e "${YELLOW}   Test keyring import: check ${WORK_DIR}/key-import.out${NC}"
  fi
else
  echo -e "${YELLOW}   dvpn-key-import.exp not found — skipping test keyring import${NC}"
fi

echo ""

# ====================
# Step 8: Summary
# ====================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  INSTALLATION COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Address : $ADDRESS"
echo ""
echo -e "${YELLOW}  ACTION REQUIRED — FUND THIS ADDRESS${NC}"
echo ""
echo "  Send DVPN tokens to:"
echo -e "  ${GREEN}$ADDRESS${NC}"
echo ""
echo "Remember to :"
echo "- Add any additional IP you will SSH from to this file : ~/sentinel-dvpncli/whitelist-gws.lst"
echo "- Edit ~/sentinel-dvpncli/.country_filter to change the allowed country list."
echo ""
echo "  Once funded, test with:"
echo "    export PATH=\$PATH:~/go/bin"
echo "    bash ~/sentinel-dvpncli/MyScripts/sentinel-balance.sh"
echo "    bash ~/sentinel-dvpncli/MyScripts/sentinel-connect.sh"
echo ""
echo "  To enable systemd service:"
echo "    sudo systemctl enable sentinel-dvpn.service"
echo "    sudo systemctl start sentinel-dvpn.service"
echo ""
echo "========================================${NC}"

# ====================
# Cleanup: remove temp files with secrets
# ====================
rm -f "${WORK_DIR}/sentinel-key.exp" "${WORK_DIR}/sentinel-key.out" "${WORK_DIR}/key-import.out"
