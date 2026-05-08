#!/usr/bin/env bash
set -euo pipefail

MASTER="k8s-user@192.168.122.10"
WORKER="k8s-user@192.168.122.12"
LABEL='app.kubernetes.io/name=socaas-shuffle-frontend'

SHUFFLE_POD_IP=$(ssh "$MASTER" "kubectl get pod -n socaas-soar -l ${LABEL} -o jsonpath='{.items[0].status.podIP}'")

if [ -z "$SHUFFLE_POD_IP" ]; then
  echo "ERROR: Could not detect Shuffle frontend pod IP"
  exit 1
fi

echo "Shuffle frontend pod IP: $SHUFFLE_POD_IP"

ssh "$WORKER" "
set -e

sudo iptables -t nat -N SOCaaS-SHUFFLE-NAT 2>/dev/null || true
sudo iptables -t nat -F SOCaaS-SHUFFLE-NAT

sudo iptables -t nat -A SOCaaS-SHUFFLE-NAT -i docker0 -p tcp --dport 30080 -j DNAT --to-destination ${SHUFFLE_POD_IP}:80

sudo iptables -t nat -C PREROUTING -i docker0 -p tcp --dport 30080 -j SOCaaS-SHUFFLE-NAT 2>/dev/null || \
sudo iptables -t nat -A PREROUTING -i docker0 -p tcp --dport 30080 -j SOCaaS-SHUFFLE-NAT

sudo iptables -t nat -C POSTROUTING -s 172.17.0.0/16 -d ${SHUFFLE_POD_IP}/32 -p tcp --dport 80 -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -s 172.17.0.0/16 -d ${SHUFFLE_POD_IP}/32 -p tcp --dport 80 -j MASQUERADE

sudo iptables -t nat -S | grep SOCaaS-SHUFFLE || true
"

echo "Done."
