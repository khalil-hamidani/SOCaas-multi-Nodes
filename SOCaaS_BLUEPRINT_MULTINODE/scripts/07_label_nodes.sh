#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Applying worker labels and verifying master taint"
ssh_node "${SOCAAS_MASTER_IP}" "bash -s" <<REMOTE
set -euo pipefail
kubectl label node ${SOCAAS_WORKER1_NAME} node-role=siem socaas.workload=siem --overwrite
kubectl label node ${SOCAAS_WORKER2_NAME} node-role=soar socaas.workload=soar --overwrite
kubectl label node ${SOCAAS_MASTER_NAME} socaas.workload=control-plane --overwrite
kubectl get nodes --show-labels
if ! kubectl describe node ${SOCAAS_MASTER_NAME} | grep -q 'node-role.kubernetes.io/control-plane:NoSchedule'; then
  echo "ERROR: control-plane taint missing on ${SOCAAS_MASTER_NAME}" >&2
  exit 1
fi
REMOTE
