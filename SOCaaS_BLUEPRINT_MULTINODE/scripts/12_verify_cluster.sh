#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Running cluster verification"
ssh_node "${SOCAAS_MASTER_IP}" "bash -s" <<'REMOTE'
set -euo pipefail
kubectl get nodes -o wide --show-labels
kubectl get pods -A -o wide
kubectl get svc -A | grep socaas || true
kubectl get pv,pvc -A | grep socaas || true
kubectl get networkpolicy -A | grep socaas || true

if kubectl get pods -A -o wide | awk '$1 ~ /^socaas-/ && $8 == "k8s-master" {found=1} END {exit found ? 0 : 1}'; then
  echo "ERROR: at least one SOC pod is scheduled on k8s-master" >&2
  kubectl get pods -A -o wide | awk '$1 ~ /^socaas-/ && $8 == "k8s-master"'
  exit 1
else
  echo "OK: no SOC pods found on k8s-master"
fi

kubectl describe node k8s-master | grep -q 'node-role.kubernetes.io/control-plane:NoSchedule' && echo "OK: master taint present"
kubectl get node k8s-worker1 --show-labels | grep -q 'node-role=siem' && echo "OK: worker1 SIEM label present"
kubectl get node k8s-worker2 --show-labels | grep -q 'node-role=soar' && echo "OK: worker2 SOAR label present"
REMOTE

log "Testing HAProxy stats and public ports from host"
curl -fsS "http://${SOCAAS_HOST_BRIDGE_IP}:${SOCAAS_HAPROXY_STATS_PORT}/stats" -u admin:admin >/dev/null || warn "HAProxy stats page not reachable"
if command -v nc >/dev/null 2>&1; then
  for port in 6443 1514 1515 55000 30002 30080 30900; do
    nc -z -w 3 "${SOCAAS_HOST_BRIDGE_IP}" "$port" && echo "port $port reachable" || warn "port $port not reachable yet"
  done
else
  warn "nc is not installed on the host; skipping TCP port reachability checks"
fi
