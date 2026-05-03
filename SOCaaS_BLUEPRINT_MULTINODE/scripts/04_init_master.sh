#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Initializing kubeadm control plane on ${SOCAAS_MASTER_NAME}"
ssh_node "${SOCAAS_MASTER_IP}" "bash -s" <<REMOTE
set -euo pipefail
if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "Kubernetes already initialized on master. Skipping kubeadm init."
else
  sudo kubeadm init \
    --apiserver-advertise-address=${SOCAAS_MASTER_IP} \
    --pod-network-cidr=${SOCAAS_POD_CIDR} \
    --service-cidr=${SOCAAS_SERVICE_CIDR}
fi
mkdir -p \$HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
kubectl get nodes || true
kubectl describe node ${SOCAAS_MASTER_NAME} | grep -A3 Taints || true
REMOTE

mkdir -p "${SOCAAS_GENERATED_DIR}/kube"
scp ${SOCAAS_SSH_OPTS:-} -i "${SOCAAS_SSH_KEY}" "${SOCAAS_VM_USER}@${SOCAAS_MASTER_IP}:/home/${SOCAAS_VM_USER}/.kube/config" "${SOCAAS_GENERATED_DIR}/kube/admin.conf" || true
log "Master initialized. Control-plane taint is intentionally kept."
