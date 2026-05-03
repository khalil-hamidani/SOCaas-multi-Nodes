#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Installing Calico ${SOCAAS_CALICO_VERSION}"
ssh_node "${SOCAAS_MASTER_IP}" "bash -s" <<REMOTE
set -euo pipefail
manifest="/tmp/socaas-calico-${SOCAAS_CALICO_VERSION}.yaml"
curl -fsSL -o "\$manifest" "https://raw.githubusercontent.com/projectcalico/calico/${SOCAAS_CALICO_VERSION}/manifests/calico.yaml"
sed -i \
  -e 's|^            # - name: CALICO_IPV4POOL_CIDR|            - name: CALICO_IPV4POOL_CIDR|' \
  -e 's|^            #   value: "192.168.0.0/16"|              value: "${SOCAAS_POD_CIDR}"|' \
  "\$manifest"
grep -A1 'CALICO_IPV4POOL_CIDR' "\$manifest"
if ! grep -q 'value: "${SOCAAS_POD_CIDR}"' "\$manifest"; then
  echo "ERROR: Calico manifest does not contain SOCAAS_POD_CIDR=${SOCAAS_POD_CIDR}" >&2
  exit 1
fi
kubectl apply -f "\$manifest"
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s
kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s
actual_cidr="\$(kubectl get ippools.crd.projectcalico.org default-ipv4-ippool -o jsonpath='{.spec.cidr}' 2>/dev/null || true)"
if [[ -n "\$actual_cidr" && "\$actual_cidr" != "${SOCAAS_POD_CIDR}" ]]; then
  echo "ERROR: Calico IPPool CIDR is \$actual_cidr but SOCAAS_POD_CIDR is ${SOCAAS_POD_CIDR}" >&2
  exit 1
fi
kubectl get nodes -o wide
REMOTE
