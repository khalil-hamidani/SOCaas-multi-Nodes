#!/usr/bin/env bash
set -euo pipefail

WORKER="k8s-user@192.168.122.12"

echo "Rolling back Shuffle Docker NAT rules on worker..."

ssh "$WORKER" '
sudo iptables -t nat -D PREROUTING -i docker0 -p tcp --dport 30080 -j SOCaaS-SHUFFLE-NAT 2>/dev/null || true
sudo iptables -t nat -F SOCaaS-SHUFFLE-NAT 2>/dev/null || true
sudo iptables -t nat -X SOCaaS-SHUFFLE-NAT 2>/dev/null || true

while sudo iptables -t nat -S POSTROUTING | grep -q "172.17.0.0/16.*dport 80.*MASQUERADE"; do
  RULE=$(sudo iptables -t nat -S POSTROUTING | grep "172.17.0.0/16.*dport 80.*MASQUERADE" | head -1 | sed "s/^-A/-D/")
  sudo iptables -t nat $RULE || true
done
'
echo "Rollback complete."
