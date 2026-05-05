#!/usr/bin/env bash
set -euo pipefail

# ===== Configuration (edit these variables only) =====
SOC_TAILSCALE_IP="100.75.201.125"
FRIEND_TAILSCALE_IP="100.91.78.126"
FRIEND_USER="zzenda"
VICTIM_VM_NAME="socaas-victim"
VICTIM_USER="victim"
AGENT_NAME="friend-victim-01"
SOC_MASTER_IP="192.168.122.10"
# =====================================================

log() { echo; echo "===== $* ====="; }

log "1. SOC health check"
ssh k8s-user@"${SOC_MASTER_IP}" '
  kubectl get pods -A | grep socaas | head -13
  kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l
'

log "2. Tailscale connectivity check"
echo "SOC Tailscale: ${SOC_TAILSCALE_IP}"
echo "Friend Tailscale: ${FRIEND_TAILSCALE_IP}"

if ! tailscale ping "${FRIEND_TAILSCALE_IP}" 2>/dev/null; then
  echo "ERROR: Cannot reach friend via Tailscale"
  exit 1
fi

log "3. Ensure victim VM is running"
ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_TAILSCALE_IP}" "
  VM_NAME='${VICTIM_VM_NAME}'
  state=\$(virsh -c qemu:///system domstate \$VM_NAME 2>/dev/null || echo missing)
  echo \"VM state: \$state\"
  if [ \"\$state\" != running ]; then
    virsh -c qemu:///system start \$VM_NAME
    sleep 30
  fi
" 2>&1 | grep -v Gtk-Message

log "4. Detect victim VM libvirt IP"
VICTIM_IP="$(
  ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_TAILSCALE_IP}" \
    "virsh -c qemu:///system domifaddr '${VICTIM_VM_NAME}' 2>/dev/null | awk '/ipv4/ {print \$4}' | cut -d/ -f1 | head -1" 2>/dev/null
)"
if [ -z "${VICTIM_IP}" ]; then
  VICTIM_IP="$(
    ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_TAILSCALE_IP}" \
      "virsh -c qemu:///system net-dhcp-leases default 2>/dev/null | awk '/${VICTIM_VM_NAME}/ {split(\$5,a,\"/\"); print a[1]}' | head -1" 2>/dev/null
  )"
fi
if [ -z "${VICTIM_IP}" ]; then
  echo "ERROR: Could not detect victim VM IP"
  exit 1
fi
echo "Victim libvirt IP: ${VICTIM_IP}"

log "5. Verify SOC ports from victim VM via Tailscale"
ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_TAILSCALE_IP}" \
  "ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_victim ${VICTIM_USER}@${VICTIM_IP} '
    SOC_TS=${SOC_TAILSCALE_IP}
    ok=0
    for port in 1514 1515 55000; do
      if nc -vz \$SOC_TS \$port 2>/dev/null; then ok=\$((ok+1)); fi
    done
    echo \"Ports OK: \$ok/3\"
    [ \$ok -eq 3 ] || { echo ERROR: Port check failed; exit 1; }
  '" 2>&1 | grep -v Gtk-Message

log "6. Update Wazuh Agent manager address to Tailscale IP"
ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_TAILSCALE_IP}" \
  "ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_victim ${VICTIM_USER}@${VICTIM_IP} '
    set -e
    SOC_TS=${SOC_TAILSCALE_IP}

    echo victim | sudo -S cp /var/ossec/etc/ossec.conf \
      /var/ossec/etc/ossec.conf.bak.tailscale.\$(date +%F_%H-%M-%S)

    echo victim | sudo -S python3 - <<PY
from pathlib import Path
import re
p = Path(\"/var/ossec/etc/ossec.conf\")
s = p.read_text()
s2 = re.sub(r\"<address>[^<]+</address>\", \"<address>\$SOC_TS</address>\", s, count=1)
if s == s2:
    raise SystemExit(\"ERROR: No address changed\")
p.write_text(s2)
print(\"Updated manager address to \$SOC_TS\")
PY

    echo victim | sudo -S systemctl restart wazuh-agent
    sleep 5
    echo victim | sudo -S systemctl is-active wazuh-agent

    echo \"Agent logs:\"
    echo victim | sudo -S grep -E \"agentd.*Connect|agentd.*server\" /var/ossec/logs/ossec.log | tail -5
  '" 2>&1 | grep -v Gtk-Message

log "7. Verify agent on SOC Manager"
ssh k8s-user@"${SOC_MASTER_IP}" \
  "kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l"

log "8. Generate test event"
ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_TAILSCALE_IP}" \
  "ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_victim ${VICTIM_USER}@${VICTIM_IP} \
    'logger \"SOCaaS Tailscale test from ${AGENT_NAME} \$(date)\"; echo Event sent'" 2>&1 | grep -v Gtk-Message | grep -v sudo

log "Done — friend endpoint using Tailscale overlay"
echo "SOC Tailscale IP  : ${SOC_TAILSCALE_IP}"
echo "Friend Tailscale IP: ${FRIEND_TAILSCALE_IP}"
echo "Victim Libvirt IP : ${VICTIM_IP}"
echo "Wazuh Agent       : ${AGENT_NAME}"
