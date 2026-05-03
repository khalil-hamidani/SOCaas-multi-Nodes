#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Installing Helm on master"
ssh_node "${SOCAAS_MASTER_IP}" "bash -s" <<'REMOTE'
set -euo pipefail
if command -v helm >/dev/null 2>&1; then
  helm version --short
  exit 0
fi
curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 /tmp/get_helm.sh
/tmp/get_helm.sh
helm version --short
REMOTE
