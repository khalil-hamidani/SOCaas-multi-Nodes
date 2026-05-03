#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

prepare_node() {
  local ip="$1" name="$2"
  log "Preparing $name at $ip"
  ssh_node "$ip" "SOCAAS_VM_STORAGE_DIR='${SOCAAS_VM_STORAGE_DIR}' SOCAAS_K8S_MINOR='${SOCAAS_K8S_MINOR}' bash -s" <<'REMOTE'
set -euo pipefail
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gpg jq gnupg lsb-release software-properties-common conntrack socat ebtables ethtool ipset chrony
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
sudo mkdir -p "${SOCAAS_VM_STORAGE_DIR}"
sudo chmod 775 "${SOCAAS_VM_STORAGE_DIR}"
cat <<'EOF' | sudo tee /etc/modules-load.d/socaas-k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<'EOF' | sudo tee /etc/sysctl.d/99-socaas-k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
vm.max_map_count = 262144
EOF
sudo sysctl --system
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd
sudo mkdir -p /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${SOCAAS_K8S_MINOR}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi
printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%s/deb/ /\n' "${SOCAAS_K8S_MINOR}" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
sudo systemctl restart containerd
kubeadm version -o short
REMOTE
}

prepare_node "${SOCAAS_MASTER_IP}" "${SOCAAS_MASTER_NAME}"
prepare_node "${SOCAAS_WORKER1_IP}" "${SOCAAS_WORKER1_NAME}"
prepare_node "${SOCAAS_WORKER2_IP}" "${SOCAAS_WORKER2_NAME}"

log "All nodes prepared"
