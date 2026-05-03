#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Preparing local PV directories on worker1 (SIEM)"
ssh_node "${SOCAAS_WORKER1_IP}" "SOCAAS_VM_STORAGE_DIR='${SOCAAS_VM_STORAGE_DIR}' bash -s" <<'REMOTE'
set -euo pipefail
sudo mkdir -p \
  "${SOCAAS_VM_STORAGE_DIR}/wazuh/indexer" \
  "${SOCAAS_VM_STORAGE_DIR}/wazuh/manager" \
  "${SOCAAS_VM_STORAGE_DIR}/wazuh/dashboard"
sudo chown -R 1000:1000 "${SOCAAS_VM_STORAGE_DIR}/wazuh"
sudo chmod -R 775 "${SOCAAS_VM_STORAGE_DIR}"
find "${SOCAAS_VM_STORAGE_DIR}" -maxdepth 3 -type d -print
REMOTE

log "Preparing local PV directories on worker2 (SOAR/IR)"
ssh_node "${SOCAAS_WORKER2_IP}" "SOCAAS_VM_STORAGE_DIR='${SOCAAS_VM_STORAGE_DIR}' bash -s" <<'REMOTE'
set -euo pipefail
sudo mkdir -p \
  "${SOCAAS_VM_STORAGE_DIR}/shuffle/backend" \
  "${SOCAAS_VM_STORAGE_DIR}/shuffle/opensearch" \
  "${SOCAAS_VM_STORAGE_DIR}/shuffle/redis" \
  "${SOCAAS_VM_STORAGE_DIR}/thehive/app" \
  "${SOCAAS_VM_STORAGE_DIR}/thehive/elasticsearch" \
  "${SOCAAS_VM_STORAGE_DIR}/cassandra" \
  "${SOCAAS_VM_STORAGE_DIR}/minio"
sudo chown -R 1000:1000 "${SOCAAS_VM_STORAGE_DIR}"
sudo chmod -R 775 "${SOCAAS_VM_STORAGE_DIR}"
find "${SOCAAS_VM_STORAGE_DIR}" -maxdepth 3 -type d -print
REMOTE

log "Local PV directories prepared"
