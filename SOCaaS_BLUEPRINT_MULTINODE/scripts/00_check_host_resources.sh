#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Checking Parrot host resources"

mountpoint -q "${SOCAAS_BASE_DIR}" || fatal "${SOCAAS_BASE_DIR} is not mounted. Run scripts/00_prepare_socaas_storage.sh after mounting the storage partition."

mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_gb=$((mem_kb / 1024 / 1024))
cpu_count=$(nproc)
disk_gb=$(socaas_free_gb)
virt_count=$(grep -Ec '(vmx|svm)' /proc/cpuinfo || true)

printf 'RAM: %s GiB\n' "$mem_gb"
printf 'CPU threads: %s\n' "$cpu_count"
printf 'Free disk on %s: %s GiB\n' "${SOCAAS_BASE_DIR}" "$disk_gb"
printf 'Virtualization CPU flags: %s\n' "$virt_count"

[[ "$mem_gb" -ge 23 ]] || warn "RAM is below 23 GiB. Low-resource mode is required and pods may OOM."
[[ "$cpu_count" -ge 10 ]] || warn "CPU thread count is below 10. Reduce VM vCPU values."
[[ "$disk_gb" -ge "$SOCAAS_MIN_FREE_GB" ]] || warn "Free disk is below SOCAAS_MIN_FREE_GB=${SOCAAS_MIN_FREE_GB} GiB. The lab may not fit comfortably."
[[ "$virt_count" -gt 0 ]] || fatal "CPU virtualization flags vmx/svm not detected. Enable virtualization in BIOS/UEFI."

if ip addr show "${SOCAAS_HOST_BRIDGE}" >/dev/null 2>&1; then
  ip addr show "${SOCAAS_HOST_BRIDGE}" | grep -q "${SOCAAS_HOST_BRIDGE_IP}" || warn "${SOCAAS_HOST_BRIDGE} exists but does not show ${SOCAAS_HOST_BRIDGE_IP}."
else
  warn "${SOCAAS_HOST_BRIDGE} not found yet. It will be created by libvirt default network."
fi

log "Resource check complete"
