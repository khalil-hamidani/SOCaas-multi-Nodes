#!/usr/bin/env bash
set -u

TARGET_IP="192.168.122.201"
PIPELINE_HEALTH_URL="http://192.168.122.1:30001/healthz"
PIPELINE_LOG_LINES="250"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

section() {
  echo
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}============================================================${NC}"
}

ok() {
  echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
}

pause_for_screenshot() {
  echo
  echo -e "${YELLOW}>>> Take screenshot now if needed, then press ENTER to continue...${NC}"
  read -r _
}

clear
section "SOCaaS Demo Evidence Script"
echo "Date: $(date)"
echo "Target victim: ${TARGET_IP}"
echo "Pipeline health: ${PIPELINE_HEALTH_URL}"
echo
echo "This script is for screenshots of deployment status and Nmap detection pipeline."
pause_for_screenshot

section "1. Kubernetes Cluster Nodes"
kubectl get nodes -o wide
pause_for_screenshot

section "2. SOCaaS Namespaces"
kubectl get ns | grep -E 'socaas|NAME' || true
pause_for_screenshot

section "3. Wazuh Deployment Status"
kubectl get pods -n socaas-siem -o wide
echo
kubectl get svc -n socaas-siem -o wide
pause_for_screenshot

section "4. Shuffle Deployment Status"
kubectl get pods -n socaas-soar -o wide
echo
kubectl get svc -n socaas-soar -o wide
pause_for_screenshot

section "5. TheHive Deployment Status"
kubectl get pods -n socaas-thehive -o wide
echo
kubectl get svc -n socaas-thehive -o wide
pause_for_screenshot

section "6. Important External SOCaaS Ports"
kubectl get svc -A -o wide | grep -E '30001|30080|30900|31514|31515|31550|wazuh|shuffle|thehive|pipeline' || true
pause_for_screenshot

section "7. Pipeline Gateway Health"
echo "Command:"
echo "curl -sS ${PIPELINE_HEALTH_URL}"
echo
curl -sS "${PIPELINE_HEALTH_URL}" || true
echo
pause_for_screenshot

section "8. Wazuh Agent Status"
kubectl exec -n socaas-siem -it socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l || true
pause_for_screenshot

section "9. Pre-Test Wazuh Nmap Rule 4100 Counter"
PRE_COUNT="$(kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- bash -lc 'grep -c "\"id\":\"4100\"" /var/ossec/logs/alerts/alerts.json || true' 2>/dev/null | tr -d '\r')"
echo "Rule 4100 alerts before scan: ${PRE_COUNT}"
echo
echo "Latest previous rule 4100 alerts:"
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- bash -lc 'grep "\"id\":\"4100\"" /var/ossec/logs/alerts/alerts.json | tail -n 3 || true'
pause_for_screenshot

section "10. Run Nmap Scan Simulation"
echo "Attack simulation command:"
echo "sudo nmap -sS -Pn -p 22,80,443,445,3389 ${TARGET_IP}"
echo
sudo nmap -sS -Pn -p 22,80,443,445,3389 "${TARGET_IP}"
echo
ok "Nmap scan completed."
echo "Waiting 60 seconds for Wazuh -> Pipeline -> Shuffle -> TheHive..."
sleep 60
pause_for_screenshot

section "11. Post-Test Wazuh Rule 4100 Detection"
POST_COUNT="$(kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- bash -lc 'grep -c "\"id\":\"4100\"" /var/ossec/logs/alerts/alerts.json || true' 2>/dev/null | tr -d '\r')"
echo "Rule 4100 alerts before scan: ${PRE_COUNT}"
echo "Rule 4100 alerts after scan : ${POST_COUNT}"
echo
echo "Latest rule 4100 alerts:"
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- bash -lc 'grep "\"id\":\"4100\"" /var/ossec/logs/alerts/alerts.json | tail -n 5 || true'
pause_for_screenshot

section "12. Latest Parsed Wazuh Nmap Alert"
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- bash -lc '
python3 - <<PY
import json
path="/var/ossec/logs/alerts/alerts.json"
last=None
try:
    with open(path, "r", errors="ignore") as f:
        for line in f:
            if "\"id\":\"4100\"" in line:
                try:
                    last=json.loads(line)
                except Exception:
                    pass
except Exception as e:
    print("Could not read alerts.json:", e)

if not last:
    print("No rule 4100 alert found.")
else:
    print("Timestamp      :", last.get("timestamp"))
    print("Rule ID        :", last.get("rule", {}).get("id"))
    print("Rule Level     :", last.get("rule", {}).get("level"))
    print("Description    :", last.get("rule", {}).get("description"))
    print("Agent ID       :", last.get("agent", {}).get("id"))
    print("Agent Name     :", last.get("agent", {}).get("name"))
    print("Agent IP       :", last.get("agent", {}).get("ip"))
    print("Source IP      :", last.get("data", {}).get("srcip"))
    print("Destination IP :", last.get("data", {}).get("dstip"))
    print("Destination Port:", last.get("data", {}).get("dstport"))
    print("Protocol       :", last.get("data", {}).get("protocol"))
    print("Location       :", last.get("location"))
PY
'
pause_for_screenshot

section "13. Pipeline Gateway Deduplication Evidence"
echo "Recent Pipeline Gateway logs containing dedup/forward/Nmap fields:"
kubectl logs -n socaas-soar deploy/socaas-pipeline-gateway --tail="${PIPELINE_LOG_LINES}" | \
grep -Ei 'dedup|duplicate|suppressed|forwarded_to_shuffle|forwarded|shuffle|accepted|4100|victim-01|192.168.122.201|192.168.122.1' || true
pause_for_screenshot

section "14. Pipeline Gateway Summary"
echo "Expected evidence:"
echo "- Pipeline health is OK"
echo "- Wazuh generated rule 4100"
echo "- Pipeline deduplicated repeated scan alerts"
echo "- Only one or few alerts forwarded to Shuffle"
echo
kubectl logs -n socaas-soar deploy/socaas-pipeline-gateway --tail="${PIPELINE_LOG_LINES}" | \
python3 - <<'PY'
import sys, re
text=sys.stdin.read()
patterns = {
    "dedup_mentions": r"dedup|duplicate|suppressed",
    "forward_mentions": r"forwarded_to_shuffle|forwarded|shuffle",
    "rule_4100_mentions": r"4100",
}
for name, pat in patterns.items():
    print(f"{name}: {len(re.findall(pat, text, flags=re.I))}")
PY
pause_for_screenshot

section "15. Final Manual Verification Checklist"
echo "Open these UIs and take screenshots:"
echo
echo "1. Shuffle workflow canvas:"
echo "   http://192.168.122.1:30080"
echo "   Expected: Webhook -> Build SOC Telegram Message -> Telegram -> Email -> TheHive Case -> Final Response"
echo
echo "2. Shuffle latest execution:"
echo "   Expected: FINISHED, all actions successful"
echo
echo "3. Telegram:"
echo "   Expected: SOCaaS alert with Rule 4100, victim-01, source IP, destination IP"
echo
echo "4. Mailtrap:"
echo "   Expected: SOCaaS email alert with the same fields"
echo
echo "5. TheHive:"
echo "   http://192.168.122.1:30900/cases"
echo "   Expected case title: [SOCaaS][CRITICAL] Rule 4100 - victim-01"
echo
ok "Evidence script completed."
