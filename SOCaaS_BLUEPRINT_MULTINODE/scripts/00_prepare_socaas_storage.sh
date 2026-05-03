#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd df
require_cmd id
require_cmd mountpoint

[[ "${SOCAAS_MIN_FREE_GB}" =~ ^[0-9]+$ ]] || fatal "SOCAAS_MIN_FREE_GB must be an integer number of GiB"

log "Preparing SOCaaS host storage under ${SOCAAS_BASE_DIR}"

if [[ ! -d "${SOCAAS_BASE_DIR}" ]]; then
  fatal "${SOCAAS_BASE_DIR} does not exist. Mount the dedicated SOCaaS partition there before running this script."
fi

if ! mountpoint -q "${SOCAAS_BASE_DIR}"; then
  findmnt "${SOCAAS_BASE_DIR}" || true
  fatal "${SOCAAS_BASE_DIR} is not a mount point. Refusing to create heavy lab data on the root filesystem."
fi

free_gb="$(socaas_free_gb)"
printf 'Free space on %s: %s GiB\n' "${SOCAAS_BASE_DIR}" "${free_gb}"
if (( free_gb < SOCAAS_MIN_FREE_GB )); then
  fatal "Free space is below SOCAAS_MIN_FREE_GB=${SOCAAS_MIN_FREE_GB} GiB"
fi

owner_user="${SUDO_USER:-$USER}"
owner_group="$(id -gn "${owner_user}")"

log "Creating host storage directory tree"
sudo install -d -m 0755 -o "${owner_user}" -g "${owner_group}" \
  "${SOCAAS_BASE_DIR}" \
  "${SOCAAS_REPO_DIR}" \
  "$(dirname "${SOCAAS_LIBVIRT_IMAGES_DIR}")" \
  "${SOCAAS_DOWNLOADS_DIR}" \
  "${SOCAAS_GENERATED_DIR}" \
  "${SOCAAS_BACKUPS_DIR}" \
  "${SOCAAS_LOGS_DIR}" \
  "${SOCAAS_RUNTIME_DIR}"

if getent passwd libvirt-qemu >/dev/null 2>&1 && getent group kvm >/dev/null 2>&1; then
  sudo install -d -m 0770 -o libvirt-qemu -g kvm "${SOCAAS_LIBVIRT_IMAGES_DIR}"
else
  sudo install -d -m 0775 -o "${owner_user}" -g "${owner_group}" "${SOCAAS_LIBVIRT_IMAGES_DIR}"
  warn "libvirt-qemu:kvm is not available yet. Rerun this script after installing libvirt."
fi

log "Checking libvirt/qemu access to ${SOCAAS_LIBVIRT_IMAGES_DIR}"
if getent passwd libvirt-qemu >/dev/null 2>&1; then
  if sudo -u libvirt-qemu test -r "${SOCAAS_LIBVIRT_IMAGES_DIR}" -a -x "${SOCAAS_LIBVIRT_IMAGES_DIR}"; then
    printf 'OK: libvirt-qemu can read and enter %s\n' "${SOCAAS_LIBVIRT_IMAGES_DIR}"
  else
    warn "libvirt-qemu cannot access ${SOCAAS_LIBVIRT_IMAGES_DIR}. Check directory ownership, ACLs, and mount options."
  fi
else
  warn "Skipping qemu access test because libvirt-qemu user does not exist yet."
fi

log "Storage layout"
printf '%s\n' \
  "${SOCAAS_REPO_DIR}" \
  "${SOCAAS_LIBVIRT_IMAGES_DIR}" \
  "${SOCAAS_DOWNLOADS_DIR}" \
  "${SOCAAS_GENERATED_DIR}" \
  "${SOCAAS_BACKUPS_DIR}" \
  "${SOCAAS_LOGS_DIR}" \
  "${SOCAAS_RUNTIME_DIR}"

log "Host storage preparation complete"
