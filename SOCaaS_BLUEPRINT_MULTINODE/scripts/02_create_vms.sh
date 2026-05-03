#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd virt-install
require_cmd qemu-img
require_cmd cloud-localds
require_cmd wget

WORKDIR="${SOCAAS_GENERATED_DIR}/vms"
IMAGE_DOWNLOAD_DIR="${SOCAAS_DOWNLOADS_DIR}/images"
BASE_IMG="${IMAGE_DOWNLOAD_DIR}/ubuntu-22.04-server-cloudimg-amd64.img"
mkdir -p "${WORKDIR}" "${IMAGE_DOWNLOAD_DIR}"

mountpoint -q "${SOCAAS_BASE_DIR}" || fatal "${SOCAAS_BASE_DIR} is not mounted. Run scripts/00_prepare_socaas_storage.sh first."
"${REPO_ROOT}/scripts/00_prepare_socaas_storage.sh"

if [[ ! -f "${SOCAAS_SSH_KEY}.pub" ]]; then
  warn "SSH public key ${SOCAAS_SSH_KEY}.pub not found. Cloud-init will still enable password login for ${SOCAAS_VM_USER}."
  SSH_KEY_LINE=""
else
  SSH_KEY_LINE="$(cat "${SOCAAS_SSH_KEY}.pub")"
fi

if [[ ! -f "$BASE_IMG" ]]; then
  log "Downloading Ubuntu 22.04 cloud image"
  wget -O "$BASE_IMG" https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

create_vm() {
  local name="$1" ip="$2" mac="$3" ram="$4" vcpus="$5" disk_gb="$6"
  local disk="${SOCAAS_LIBVIRT_IMAGES_DIR}/${name}.qcow2"
  local seed="${WORKDIR}/${name}-seed.iso"
  local user_data="${WORKDIR}/${name}-user-data.yaml"
  local meta_data="${WORKDIR}/${name}-meta-data.yaml"
  local net_data="${WORKDIR}/${name}-network-config.yaml"

  if virsh -c qemu:///system dominfo "$name" >/dev/null 2>&1; then
    warn "VM $name already exists. Skipping creation."
    return 0
  fi

  if sudo test -e "$disk"; then
    fatal "Disk $disk already exists but VM $name is not defined. Refusing to overwrite it."
  fi

  log "Creating cloud-init seed for $name"
  cat > "$user_data" <<EOF_USER
#cloud-config
hostname: ${name}
manage_etc_hosts: true
ssh_pwauth: true
users:
  - name: ${SOCAAS_VM_USER}
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    plain_text_passwd: ${SOCAAS_VM_PASSWORD}
    ssh_authorized_keys:
      - ${SSH_KEY_LINE}
package_update: true
packages:
  - qemu-guest-agent
  - openssh-server
runcmd:
  - systemctl enable --now qemu-guest-agent
  - systemctl enable --now ssh
  - sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart ssh
EOF_USER

  cat > "$meta_data" <<EOF_META
instance-id: ${name}
local-hostname: ${name}
EOF_META

  cat > "$net_data" <<EOF_NET
version: 2
ethernets:
  enp1s0:
    dhcp4: false
    addresses:
      - ${ip}/24
    routes:
      - to: default
        via: ${SOCAAS_GATEWAY_IP}
    nameservers:
      addresses:
        - 1.1.1.1
        - 8.8.8.8
EOF_NET

  cloud-localds -v --network-config="$net_data" "$seed" "$user_data" "$meta_data"

  log "Creating disk $disk"
  sudo qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$disk" "${disk_gb}G"
  if getent passwd libvirt-qemu >/dev/null 2>&1 && getent group kvm >/dev/null 2>&1; then
    sudo chown libvirt-qemu:kvm "$disk"
    sudo chmod 0660 "$disk"
  fi

  log "Installing VM $name"
  sudo virt-install \
    --name "$name" \
    --ram "$ram" \
    --vcpus "$vcpus" \
    --disk "path=${disk},format=qcow2,bus=virtio" \
    --disk "path=${seed},device=cdrom" \
    --os-variant ubuntu22.04 \
    --network "network=default,model=virtio,mac=${mac}" \
    --graphics none \
    --console pty,target_type=serial \
    --import \
    --noautoconsole
}

create_vm "${SOCAAS_MASTER_NAME}" "${SOCAAS_MASTER_IP}" "${SOCAAS_MASTER_MAC}" "${SOCAAS_MASTER_RAM_MB}" "${SOCAAS_MASTER_VCPU}" "${SOCAAS_MASTER_DISK_GB}"
create_vm "${SOCAAS_WORKER1_NAME}" "${SOCAAS_WORKER1_IP}" "${SOCAAS_WORKER1_MAC}" "${SOCAAS_WORKER_RAM_MB}" "${SOCAAS_WORKER_VCPU}" "${SOCAAS_WORKER1_DISK_GB}"
create_vm "${SOCAAS_WORKER2_NAME}" "${SOCAAS_WORKER2_IP}" "${SOCAAS_WORKER2_MAC}" "${SOCAAS_WORKER_RAM_MB}" "${SOCAAS_WORKER_VCPU}" "${SOCAAS_WORKER2_DISK_GB}"

log "VM creation requested. Cloud-init can take a few minutes after first boot."
virsh -c qemu:///system list --all
