#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

LOCAL_RENDER_DIR="${SOCAAS_GENERATED_DIR}/helm"
REMOTE_RENDER_DIR="${SOCAAS_VM_STORAGE_DIR}/generated/helm"
mkdir -p "${LOCAL_RENDER_DIR}"

log "Copying repository to master"
ssh_node "${SOCAAS_MASTER_IP}" "rm -rf ~/SOCaaS_BLUEPRINT_MULTINODE && mkdir -p ~/SOCaaS_BLUEPRINT_MULTINODE"
rsync -az --delete -e "ssh ${SOCAAS_SSH_OPTS:-} -i ${SOCAAS_SSH_KEY}" \
  "${REPO_ROOT}/" "${SOCAAS_VM_USER}@${SOCAAS_MASTER_IP}:~/SOCaaS_BLUEPRINT_MULTINODE/"

log "Deploying SOCaaS Helm chart"
ssh_node "${SOCAAS_MASTER_IP}" "bash -s" <<REMOTE
set -euo pipefail
cd ~/SOCaaS_BLUEPRINT_MULTINODE
sudo install -d -m 0755 -o "\$(id -u)" -g "\$(id -g)" "${REMOTE_RENDER_DIR}"

# Pre-create release namespace with Helm labels so chart's Namespace resource is a no-op
kubectl create ns ${SOCAAS_HELM_NAMESPACE} 2>/dev/null || true
kubectl label ns ${SOCAAS_HELM_NAMESPACE} app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate ns ${SOCAAS_HELM_NAMESPACE} meta.helm.sh/release-name=${SOCAAS_HELM_RELEASE} --overwrite
kubectl annotate ns ${SOCAAS_HELM_NAMESPACE} meta.helm.sh/release-namespace=${SOCAAS_HELM_NAMESPACE} --overwrite

helm lint charts/socaas -f charts/socaas/values-multinode.yaml
helm template ${SOCAAS_HELM_RELEASE} charts/socaas -f charts/socaas/values-multinode.yaml > "${REMOTE_RENDER_DIR}/socaas-rendered.yaml"
helm upgrade --install ${SOCAAS_HELM_RELEASE} charts/socaas \
  --namespace ${SOCAAS_HELM_NAMESPACE} \
  -f charts/socaas/values-multinode.yaml \
  --set-string secrets.wazuh.adminUser="${SOCAAS_WAZUH_ADMIN_USER}" \
  --set-string secrets.wazuh.adminPassword="${SOCAAS_WAZUH_ADMIN_PASSWORD}" \
  --set-string secrets.shuffle.adminEmail="${SOCAAS_SHUFFLE_ADMIN_EMAIL}" \
  --set-string secrets.shuffle.adminPassword="${SOCAAS_SHUFFLE_ADMIN_PASSWORD}" \
  --set-string secrets.thehive.secret="${SOCAAS_THEHIVE_SECRET}" \
  --set-string secrets.thehive.minioAccessKey="${SOCAAS_MINIO_ACCESS_KEY}" \
  --set-string secrets.thehive.minioSecretKey="${SOCAAS_MINIO_SECRET_KEY}" \
  --set-string secrets.pipeline.sharedSecret="${SOCAAS_PIPELINE_SHARED_SECRET}" \
  --set-string pipeline.nativeShuffleWebhookUrl="${SOCAAS_NATIVE_SHUFFLE_WEBHOOK_URL}" \
  --set-string secrets.pipeline.virustotalApiKey="${SOCAAS_VIRUSTOTAL_API_KEY:-}" \
  --timeout 20m \
  --wait
kubectl get pods -A -o wide | grep socaas || true
REMOTE

scp ${SOCAAS_SSH_OPTS:-} -i "${SOCAAS_SSH_KEY}" \
  "${SOCAAS_VM_USER}@${SOCAAS_MASTER_IP}:${REMOTE_RENDER_DIR}/socaas-rendered.yaml" \
  "${LOCAL_RENDER_DIR}/socaas-rendered.yaml" || warn "Could not copy rendered Helm manifest to ${LOCAL_RENDER_DIR}"
