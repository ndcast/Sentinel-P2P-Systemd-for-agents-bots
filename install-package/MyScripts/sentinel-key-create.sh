#!/bin/bash
set -euo pipefail

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../sentinel-env.sh" ]]; then
  source "${SCRIPT_DIR}/../sentinel-env.sh"
elif [[ -f "${HOME}/sentinel-dvpncli/sentinel-env.sh" ]]; then
  source "${HOME}/sentinel-dvpncli/sentinel-env.sh"
fi

WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
KEYRING_BACKEND="${KEYRING_BACKEND:-test}"
KEY_NAME="${KEY_NAME:-main}"

PASSPHRASE_FILE="${WORK_DIR}/.passphrase"
MNEMONIC_FILE="${WORK_DIR}/.mnemonic"
ADDRESS_FILE="${WORK_DIR}/.address"

if [[ ! -f "$PASSPHRASE_FILE" ]]; then
 echo "Error: $PASSPHRASE_FILE not found!"
 exit 1
fi

PASSPHRASE=$(cat "$PASSPHRASE_FILE" | tr -d '\n\r')

echo "Creating Sentinel key '$KEY_NAME' (v4.x)..."

# Use expect — empty mnemonic triggers auto-generation
if command -v expect >/dev/null; then
 OUTPUT=$(expect -c "
 set timeout 30
 spawn sentinel-dvpncli keys add $KEY_NAME --keyring.backend $KEYRING_BACKEND --home $WORK_DIR
 expect \"Enter your BIP-39 mnemonic\"
 send \"\r\"
 expect \"Enter your BIP-39 passphrase\"
 send \"\r\"
 expect \"Enter keyring passphrase\"
 send \"$PASSPHRASE\r\"
 expect \"Enter keyring passphrase again:\"
 send \"$PASSPHRASE\r\"
 expect eof
 " 2>&1)
else
 echo "Error: expect is required but not installed"
 exit 1
fi

echo "$OUTPUT"

# Extract address
ADDRESS=$(echo "$OUTPUT" | grep -oE 'address: sent1[a-z0-9]+' | awk '{print $2}' | head -n1)

# Extract mnemonic (24 words)
MNEMONIC=$(echo "$OUTPUT" | grep -oE '([a-z]+[[:space:]]+){23}[a-z]+' | tail -n1 | xargs)

if [[ -z "$ADDRESS" ]]; then
 echo "❌ Could not extract address"
 exit 1
fi

if [[ $(wc -w <<< "$MNEMONIC") -ne 24 ]]; then
 echo "❌ Could not extract 24-word mnemonic"
 exit 1
fi

echo "$MNEMONIC" > "$MNEMONIC_FILE"
chmod 600 "$MNEMONIC_FILE"
echo "ADDRESS=\"$ADDRESS\"" > "$ADDRESS_FILE"

echo "✅ Success!"
echo "Address : $ADDRESS"
echo "Mnemonic saved → $MNEMONIC_FILE"
echo "Address saved → $ADDRESS_FILE"