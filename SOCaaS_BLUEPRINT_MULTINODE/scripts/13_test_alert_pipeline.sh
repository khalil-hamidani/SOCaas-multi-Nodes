#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Sending deterministic Wazuh-style alert to the SOCaaS pipeline gateway"
ssh_node "${SOCAAS_MASTER_IP}" "bash -s" <<REMOTE
set -euo pipefail
kubectl -n socaas-siem run socaas-alert-test --rm -i --restart=Never --image=curlimages/curl:8.8.0 -- \
  curl -sS -X POST http://socaas-pipeline-gateway.socaas-soar.svc.cluster.local:8080/hooks/wazuh \
    -H 'Content-Type: application/json' \
    -H 'X-SOCaaS-Webhook-Secret: ${SOCAAS_PIPELINE_SHARED_SECRET}' \
    -d '{"source":"wazuh","rule":{"id":"100400","level":10,"description":"SOCaaS test suspicious command"},"agent":{"id":"001","name":"external-laptop","ip":"192.168.122.50"},"data":{"command":"logger SOCaaS pipeline test"}}'

echo
kubectl logs -n socaas-soar deployment/socaas-pipeline-gateway --tail=50
REMOTE
