#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Creating kubeadm join command on master"
join_cmd=$(ssh_node "${SOCAAS_MASTER_IP}" "kubeadm token create --print-join-command")
mkdir -p "${SOCAAS_GENERATED_DIR}/kube"
printf '%s\n' "$join_cmd" | tee "${SOCAAS_GENERATED_DIR}/kube/kubeadm-join-command.txt"

join_worker() {
  local ip="$1" name="$2"
  log "Joining $name"
  ssh_node "$ip" "bash -s" <<REMOTE
set -euo pipefail
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo "$name already appears joined. Skipping."
else
  sudo ${join_cmd}
fi
REMOTE
}

join_worker "${SOCAAS_WORKER1_IP}" "${SOCAAS_WORKER1_NAME}"
join_worker "${SOCAAS_WORKER2_IP}" "${SOCAAS_WORKER2_NAME}"

ssh_node "${SOCAAS_MASTER_IP}" "kubectl get nodes -o wide"
