#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

errors=0

ok() { printf 'OK: %s\n' "$*"; }
bad() { printf 'WARN: %s\n' "$*" >&2; errors=1; }

log "Verifying SOCaaS storage layout"

if mountpoint -q "${SOCAAS_BASE_DIR}"; then
  ok "${SOCAAS_BASE_DIR} is mounted"
else
  bad "${SOCAAS_BASE_DIR} is not mounted"
fi

printf 'Free space on %s: %s GiB\n' "${SOCAAS_BASE_DIR}" "$(socaas_free_gb 2>/dev/null || printf 'unknown')"

log "Environment variables"
for var in \
  SOCAAS_BASE_DIR \
  SOCAAS_REPO_DIR \
  SOCAAS_LIBVIRT_IMAGES_DIR \
  SOCAAS_DOWNLOADS_DIR \
  SOCAAS_GENERATED_DIR \
  SOCAAS_BACKUPS_DIR \
  SOCAAS_LOGS_DIR \
  SOCAAS_RUNTIME_DIR \
  SOCAAS_VM_STORAGE_DIR \
  SOCAAS_MASTER_DISK_GB \
  SOCAAS_WORKER1_DISK_GB \
  SOCAAS_WORKER2_DISK_GB \
  SOCAAS_POD_CIDR; do
  printf '%s=%s\n' "$var" "${!var}"
done

log "Host directories"
for dir in \
  "${SOCAAS_REPO_DIR}" \
  "${SOCAAS_LIBVIRT_IMAGES_DIR}" \
  "${SOCAAS_DOWNLOADS_DIR}" \
  "${SOCAAS_GENERATED_DIR}" \
  "${SOCAAS_BACKUPS_DIR}" \
  "${SOCAAS_LOGS_DIR}" \
  "${SOCAAS_RUNTIME_DIR}"; do
  if [[ -d "$dir" ]]; then
    ok "$dir exists"
  else
    bad "$dir is missing"
  fi
done

log "Configured VM disk locations"
for vm in "${SOCAAS_MASTER_NAME}" "${SOCAAS_WORKER1_NAME}" "${SOCAAS_WORKER2_NAME}"; do
  disk="${SOCAAS_LIBVIRT_IMAGES_DIR}/${vm}.qcow2"
  if sudo test -f "$disk"; then
    ok "$vm disk is at $disk"
    if command -v qemu-img >/dev/null 2>&1; then
      sudo qemu-img info "$disk" | awk -v vm="$vm" '/virtual size|disk size|backing file/ {print vm ": " $0}'
    fi
  else
    bad "$vm disk not found at $disk"
  fi
done

if command -v virsh -c qemu:///system >/dev/null 2>&1; then
  log "libvirt domain block devices"
  for vm in "${SOCAAS_MASTER_NAME}" "${SOCAAS_WORKER1_NAME}" "${SOCAAS_WORKER2_NAME}"; do
    if virsh -c qemu:///system dominfo "$vm" >/dev/null 2>&1; then
      virsh -c qemu:///system domblklist "$vm" --details || true
    else
      printf '%s is not defined in libvirt yet\n' "$vm"
    fi
  done
fi

log "Unexpected qcow2 files under /var/lib/libvirt/images"
if [[ -d /var/lib/libvirt/images ]]; then
  if [[ "$(readlink -f /var/lib/libvirt/images)" == "$(readlink -f "${SOCAAS_LIBVIRT_IMAGES_DIR}")" ]]; then
    ok "/var/lib/libvirt/images resolves to ${SOCAAS_LIBVIRT_IMAGES_DIR}"
  else
    mapfile -t unexpected_qcow2 < <(sudo find /var/lib/libvirt/images -maxdepth 1 -type f -name '*.qcow2' -print 2>/dev/null | sort)
    if (( ${#unexpected_qcow2[@]} == 0 )); then
      ok "no qcow2 files found in /var/lib/libvirt/images"
    else
      bad "qcow2 files exist in /var/lib/libvirt/images"
      printf '%s\n' "${unexpected_qcow2[@]}"
    fi
  fi
else
  ok "/var/lib/libvirt/images does not exist"
fi

log "Generated files"
case "${SOCAAS_GENERATED_DIR}" in
  "${SOCAAS_BASE_DIR}"/*) ok "generated files are configured under ${SOCAAS_BASE_DIR}" ;;
  *) bad "SOCAAS_GENERATED_DIR is outside ${SOCAAS_BASE_DIR}" ;;
esac
if [[ -d "${SOCAAS_GENERATED_DIR}" ]]; then
  find "${SOCAAS_GENERATED_DIR}" -maxdepth 3 -type f -print | sort | sed -n '1,40p'
fi

if (( errors == 0 )); then
  log "Storage verification completed without warnings"
else
  warn "Storage verification completed with warnings"
fi

exit "$errors"
