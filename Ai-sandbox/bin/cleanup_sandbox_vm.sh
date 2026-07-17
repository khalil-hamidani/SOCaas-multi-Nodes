#!/bin/bash
VM_NAME="${1:?Usage: cleanup_sandbox_vm.sh <vm_name>}"
DISK_DIR="/var/lib/libvirt/images/socaas-sandbox"
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --nvram 2>/dev/null || true
rm -f "${DISK_DIR}/${VM_NAME}.qcow2" 2>/dev/null || true
echo "Cleaned up: $VM_NAME"
