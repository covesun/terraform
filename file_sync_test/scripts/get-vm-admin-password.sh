#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -gt 2 ]]; then
  echo "Usage: ./scripts/get-vm-admin-password.sh [KEY_VAULT_NAME] [SECRET_NAME]"
  exit 1
fi

if [[ $# -ge 1 ]]; then
  KEY_VAULT_NAME="$1"
else
  KEY_VAULT_NAME="$(terraform -chdir="${PROJECT_DIR}" output -raw key_vault_name)"
fi

if [[ $# -eq 2 ]]; then
  SECRET_NAME="$2"
else
  SECRET_NAME="$(terraform -chdir="${PROJECT_DIR}" output -raw admin_password_secret_name)"
fi

az keyvault secret show \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --query value -o tsv
