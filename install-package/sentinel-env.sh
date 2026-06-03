#!/bin/bash
# Sentinel dVPN — Environment Loader
# Source this in all scripts: source sentinel-env.sh
# Resolves .env from script location or HOME

resolve_env() {
  local env_file=""
  # Try script directory first (for MyScripts/ context)
  if [[ -n "${BASH_SOURCE[0]}" ]]; then
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local candidate="${script_dir}/.env"
    if [[ -f "$candidate" ]]; then
      env_file="$candidate"
    fi
  fi
  # Fallback to HOME
  if [[ -z "$env_file" ]] && [[ -f "${HOME}/.env" ]]; then
    env_file="${HOME}/.env"
  fi
  # Fallback to WORK_DIR
  if [[ -z "$env_file" ]]; then
    local work_dir="${HOME}/sentinel-dvpncli"
    if [[ -f "${work_dir}/.env" ]]; then
      env_file="${work_dir}/.env"
    fi
  fi
  echo "$env_file"
}

ENV_FILE="$(resolve_env)"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "Warning: .env not found (tried: $ENV_FILE). Using defaults."
  WORK_DIR="${WORK_DIR:-${HOME}/sentinel-dvpncli}"
  RPC_ENDPOINTS="${RPC_ENDPOINTS:-https://sentinel-rpc.polkachu.com:443,https://sentinel-rpc.publicnode.com:443}"
  LCD_ENDPOINT="${LCD_ENDPOINT:-https://lcd.sentinel.co}"
  KEY_NAME="${KEY_NAME:-main}"
  KEYRING_BACKEND="${KEYRING_BACKEND:-test}"
  KEYRING_HOME="${KEYRING_HOME:-${WORK_DIR}}"
  COUNTRY_FILTER="${COUNTRY_FILTER:-NL,DE,FR}"
  DEFAULT_GIGABYTES="${DEFAULT_GIGABYTES:-10}"
  DEFAULT_HOURS="${DEFAULT_HOURS:-0}"
  TX_GAS_PRICES="${TX_GAS_PRICES:-0.1udvpn}"
  TX_GAS_ADJUSTMENT="${TX_GAS_ADJUSTMENT:-1.8}"
  MAX_PRICE="${MAX_PRICE:-udvpn:1,30000}"
fi