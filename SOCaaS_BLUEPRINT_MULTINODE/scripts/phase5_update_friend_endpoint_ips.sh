#!/usr/bin/env bash
set -euo pipefail

# ===== Configuration (edit these variables only) =====
SOC_IP="192.168.182.203"
FRIEND_HOST_IP="192.168.182.201"
FRIEND_USER="zzenda"
VICTIM_VM_NAME="socaas-victim"
VICTIM_USER="victim"
AGENT_NAME="friend-victim-01"
SOC_MASTER_IP="192.168.122.10"
# =====================================================

log() { echo; echo "===== $* ====="; }

run_friend() {
  ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_HOST_IP}" "$@"
}

run_victim() {
  run_friend "ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_victim ${VICTIM_USER}@${1}" "${@:2}"
}

log "1. Check SOC host IP and listening ports"
ip -4 -br addr
sudo ss -ltnup 2>/dev/null | grep -E ':1514|:1515|:55000|:30002|:30080|:30900' || true

log "2. Check friend host"
run_friend "hostname; ip -4 -br addr; virsh -c qemu:///system list --all"

log "3. Test friend host to SOC ports"
run_friend "SOC_IP='${SOC_IP}'; echo Target \$SOC_IP; for port in 1514 1515 55000 30002 30080 30900; do printf '  %s:%s -> ' \$SOC_IP \$port; nc -vz \$SOC_IP \$port 2>&1 | tail -1 || true; done"

log "4. Ensure victim VM is running"
run_friend "
  VM_NAME='${VICTIM_VM_NAME}'
  state=\$(virsh -c qemu:///system domstate \$VM_NAME 2>/dev/null || echo missing)
  echo \"VM state: \$state\"
  if [ \"\$state\" != running ]; then
    echo \"Starting \$VM_NAME...\"
    virsh -c qemu:///system start \$VM_NAME
    sleep 30
  fi
  virsh -c qemu:///system list --all
"

log "5. Detect victim VM IP"
VICTIM_IP="$(
  run_friend "virsh -c qemu:///system domifaddr '${VICTIM_VM_NAME}' 2>/dev/null | awk '/ipv4/ {print \$4}' | cut -d/ -f1 | head -1"
)"

if [ -z "${VICTIM_IP}" ]; then
  VICTIM_IP="$(
    run_friend "virsh -c qemu:///system net-dhcp-leases default 2>/dev/null | awk '/${VICTIM_VM_NAME}/ {split(\$5,a,\"/\"); print a[1]}' | head -1"
  )"
fi

if [ -z "${VICTIM_IP}" ]; then
  echo "ERROR: Could not detect victim VM IP"
  exit 1
fi

echo "Detected victim IP: ${VICTIM_IP}"

log "6. Reconfigure Wazuh Agent on victim VM"
export VICTIM_IP SOC_IP AGENT_NAME VICTIM_USER FRIEND_USER FRIEND_HOST_IP
bash -c '
  ssh -o StrictHostKeyChecking=accept-new "${FRIEND_USER}@${FRIEND_HOST_IP}" "
    ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_victim ${VICTIM_USER}@${VICTIM_IP} \"
set -e

echo \"--- Victim host ---\"
hostname
ip -4 -br addr

echo \"--- Test SOC ports from victim ---\"
for port in 1514 1515 55000; do
  echo \"Testing \\\${SOC_IP}:\\\$port\"
  nc -vz \\\${SOC_IP} \\\$port || echo \"WARN: port \\\$port not reachable\"
done

echo \"--- Backup ossec.conf ---\"
sudo cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.\\\$(date +%F_%H-%M-%S)
ls -la /var/ossec/etc/ossec.conf.bak.* 2>/dev/null | tail -1 || true

echo \"--- Update manager address to \\\${SOC_IP} ---\"
sudo python3 - <<PY
from pathlib import Path
import re
p = Path(\"/var/ossec/etc/ossec.conf\")
s = p.read_text()
s2 = re.sub(r\"<address>[^<]+</address>\", \"<address>\\\${SOC_IP}</address>\", s, count=1)
if s == s2:
    raise SystemExit(\"ERROR: No manager address entry found in ossec.conf\")
p.write_text(s2)
print(\"Updated manager address to \\\${SOC_IP}\")
PY

echo \"--- Restart Wazuh agent ---\"
sudo systemctl restart wazuh-agent
sleep 5
sudo systemctl is-active wazuh-agent

echo \"--- Agent logs (last 25) ---\"
sudo tail -n 25 /var/ossec/logs/ossec.log
\"
  "
'

log "7. Verify agent on SOC Manager"
ssh k8s-user@"${SOC_MASTER_IP}" "kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l"

log "8. Generate test event from victim"
ssh "${FRIEND_USER}@${FRIEND_HOST_IP}" "ssh -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519_victim ${VICTIM_USER}@${VICTIM_IP} 'logger \"SOCaaS IP update test from ${AGENT_NAME} \$(date)\"'"

log "Done — friend endpoint reconnected to SOC IP ${SOC_IP}"
echo "Victim VM: ${VICTIM_VM_NAME} @ ${VICTIM_IP}"
echo "Agent   : ${AGENT_NAME}"
echo "Manager : ${SOC_IP}:1514"
