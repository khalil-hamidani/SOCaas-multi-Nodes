#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/env/socaas.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/env/socaas.env.example"
fi

: "${SOCAAS_BASE_DIR:=/srv/socaas}"
: "${SOCAAS_REPO_DIR:=${SOCAAS_BASE_DIR}/repo}"
: "${SOCAAS_LIBVIRT_IMAGES_DIR:=${SOCAAS_BASE_DIR}/libvirt/images}"
: "${SOCAAS_DOWNLOADS_DIR:=${SOCAAS_BASE_DIR}/downloads}"
: "${SOCAAS_GENERATED_DIR:=${SOCAAS_BASE_DIR}/generated}"
: "${SOCAAS_BACKUPS_DIR:=${SOCAAS_BASE_DIR}/backups}"
: "${SOCAAS_LOGS_DIR:=${SOCAAS_BASE_DIR}/logs}"
: "${SOCAAS_RUNTIME_DIR:=${SOCAAS_BASE_DIR}/runtime}"
: "${SOCAAS_VM_STORAGE_DIR:=/srv/socaas}"
: "${SOCAAS_MIN_FREE_GB:=220}"
: "${SOCAAS_MASTER_DISK_GB:=50}"
: "${SOCAAS_WORKER_DISK_GB:=120}"
: "${SOCAAS_WORKER1_DISK_GB:=${SOCAAS_WORKER_DISK_GB}}"
: "${SOCAAS_WORKER2_DISK_GB:=${SOCAAS_WORKER_DISK_GB}}"
: "${SOCAAS_POD_CIDR:=10.244.0.0/16}"

SOCAAS_BASE_DIR="${SOCAAS_BASE_DIR%/}"
SOCAAS_REPO_DIR="${SOCAAS_REPO_DIR%/}"
SOCAAS_LIBVIRT_IMAGES_DIR="${SOCAAS_LIBVIRT_IMAGES_DIR%/}"
SOCAAS_DOWNLOADS_DIR="${SOCAAS_DOWNLOADS_DIR%/}"
SOCAAS_GENERATED_DIR="${SOCAAS_GENERATED_DIR%/}"
SOCAAS_BACKUPS_DIR="${SOCAAS_BACKUPS_DIR%/}"
SOCAAS_LOGS_DIR="${SOCAAS_LOGS_DIR%/}"
SOCAAS_RUNTIME_DIR="${SOCAAS_RUNTIME_DIR%/}"
SOCAAS_VM_STORAGE_DIR="${SOCAAS_VM_STORAGE_DIR%/}"

export SOCAAS_BASE_DIR SOCAAS_REPO_DIR SOCAAS_LIBVIRT_IMAGES_DIR
export SOCAAS_DOWNLOADS_DIR SOCAAS_GENERATED_DIR SOCAAS_BACKUPS_DIR
export SOCAAS_LOGS_DIR SOCAAS_RUNTIME_DIR SOCAAS_VM_STORAGE_DIR
export SOCAAS_MIN_FREE_GB SOCAAS_MASTER_DISK_GB SOCAAS_WORKER_DISK_GB
export SOCAAS_WORKER1_DISK_GB SOCAAS_WORKER2_DISK_GB SOCAAS_POD_CIDR

log() { printf '\n[SOCAAS] %s\n' "$*"; }
warn() { printf '\n[SOCAAS:WARN] %s\n' "$*" >&2; }
fatal() { printf '\n[SOCAAS:ERROR] %s\n' "$*" >&2; exit 1; }

validate_storage_paths() {
  local var value

  [[ "${SOCAAS_BASE_DIR}" == "/srv/socaas" ]] || fatal "SOCAAS_BASE_DIR must be /srv/socaas, not ${SOCAAS_BASE_DIR}"

  for var in \
    SOCAAS_BASE_DIR \
    SOCAAS_REPO_DIR \
    SOCAAS_LIBVIRT_IMAGES_DIR \
    SOCAAS_DOWNLOADS_DIR \
    SOCAAS_GENERATED_DIR \
    SOCAAS_BACKUPS_DIR \
    SOCAAS_LOGS_DIR \
    SOCAAS_RUNTIME_DIR \
    SOCAAS_VM_STORAGE_DIR; do
    value="${!var}"
    [[ "${value}" == /srv/socaas* ]] || fatal "${var} must live under /srv/socaas, not ${value}"
    [[ "${value}" != /src/socaas* ]] || fatal "${var} uses the invalid /src/socaas path"
  done
}

socaas_free_gb() {
  df -BG "${SOCAAS_BASE_DIR}" | awk 'NR==2 {gsub("G","",$4); print $4}'
}

validate_storage_paths

ssh_node() {
  local ip="$1"; shift
  ssh ${SOCAAS_SSH_OPTS:-} -i "${SOCAAS_SSH_KEY}" "${SOCAAS_VM_USER}@${ip}" "$@"
}

scp_to_node() {
  local src="$1" ip="$2" dst="$3"
  scp ${SOCAAS_SSH_OPTS:-} -i "${SOCAAS_SSH_KEY}" -r "$src" "${SOCAAS_VM_USER}@${ip}:${dst}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "Missing required command: $1"
}

confirm_danger() {
  local prompt="$1"
  printf '%s\n' "$prompt"
  read -r answer
  [[ "$answer" == "DELETE_SOCAAS_LAB" ]] || fatal "Confirmation failed. Aborting."
}
