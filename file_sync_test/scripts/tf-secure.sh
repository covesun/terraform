#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/tf-secure.sh init
  ./scripts/tf-secure.sh plan
  ./scripts/tf-secure.sh apply
  ./scripts/tf-secure.sh destroy
  ./scripts/tf-secure.sh show-registered [RESOURCE_GROUP] [STORAGE_SYNC_SERVICE]
  ./scripts/tf-secure.sh get-password [KEY_VAULT_NAME] [SECRET_NAME]

Notes:
  - admin_password は Terraform がランダム生成して Key Vault へ保存する。
EOF
}

run_terraform() {
  local cmd="$1"
  cd "${PROJECT_DIR}"
  terraform -chdir="${PROJECT_DIR}" "${cmd}"
}

cmd="${1:-}"

case "${cmd}" in
  init)
    run_terraform init
    ;;
  plan)
    run_terraform plan
    ;;
  apply)
    run_terraform apply
    ;;
  destroy)
    run_terraform destroy
    ;;
  show-registered)
    rg="${2:-rg-filesync}"
    svc="${3:-filesync-svc}"
    az storagesync registered-server list \
      --resource-group "${rg}" \
      --storage-sync-service "${svc}" \
      --query "[].{id:id,name:name}" -o table
    ;;
  get-password)
    if [[ $# -gt 3 ]]; then
      echo "Usage: ./scripts/tf-secure.sh get-password [KEY_VAULT_NAME] [SECRET_NAME]"
      exit 1
    fi
    if [[ -n "${2:-}" ]]; then
      kv_name="${2}"
    else
      kv_name="$(terraform -chdir="${PROJECT_DIR}" output -raw key_vault_name)"
    fi
    if [[ -n "${3:-}" ]]; then
      secret_name="${3}"
    else
      secret_name="$(terraform -chdir="${PROJECT_DIR}" output -raw admin_password_secret_name)"
    fi
    az keyvault secret show \
      --vault-name "${kv_name}" \
      --name "${secret_name}" \
      --query value -o tsv
    ;;
  *)
    usage
    exit 1
    ;;
esac
