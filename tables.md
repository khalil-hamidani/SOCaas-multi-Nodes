# SOCaaS Operational Reference

> **⚠️ LAB ONLY — ROTATE ALL SECRETS BEFORE PRODUCTION ⚠️**
>
> This document contains FULL lab credentials, API keys, and tokens.
> These are for PFE/lab use only. Never reuse in production.
> Re-generate all secrets before any production deployment.

---

## 1. VM Infrastructure

| Component    | Hostname        | IP              | vCPU | RAM   | Disk | Role                  | Status  |
|--------------|-----------------|-----------------|------|-------|------|-----------------------|---------|
| k8s-master   | `k8s-master`    | 192.168.122.10  | 2    | 4 GB  | 50 GB| K8s control-plane     | Running |
| k8s-worker1  | `k8s-worker1`   | 192.168.122.11  | 4    | 8 GB  | 120 GB| SIEM workloads (Wazuh)| Running |
| k8s-worker2  | `k8s-worker2`   | 192.168.122.12  | 4    | 8 GB  | 120 GB| SOAR + TheHive        | Running |

**Hypervisor:** KVM/QEMU (libvirt), bridge `virbr0` on `192.168.122.0/24`

**VM SSH access:**
```
User:     k8s-user
Key:      ~/.ssh/id_ed25519
Password: OkjjOCtBKcpNkxX7r8FG           # LAB SECRET
```

---

## 2. Kubernetes Namespaces

| Namespace         | Purpose                                               |
|--------------------|-------------------------------------------------------|
| `socaas-system`   | Helm release state, shared resources                  |
| `socaas-siem`     | Wazuh SIEM (manager, indexer, dashboard)              |
| `socaas-soar`     | Shuffle SOAR, Redis, pipeline gateway, OpenSearch     |
| `socaas-thehive`  | TheHive case management, Cassandra, MinIO, ES         |
| `default`         | Kubernetes default                                     |
| `kube-system`     | Core cluster components                               |

---

## 3. Service URLs

| Service             | URL                                          | Notes                                |
|----------------------|----------------------------------------------|--------------------------------------|
| Wazuh Dashboard      | `http://192.168.122.1:30002`                 | NodePort via HAProxy on host         |
| Shuffle (Frontend)   | `http://192.168.122.1:30080`                 | NodePort via HAProxy on host         |
| TheHive UI           | `http://192.168.122.1:30900`                 | NodePort via HAProxy on host         |
| Pipeline Webhook     | `http://192.168.122.1:30000/hooks/wazuh`     | HAProxy → socaas-pipeline-gateway   |
| Pipeline Health      | `http://192.168.122.1:30000/healthz`         | Health check endpoint                |
| Shuffle Native Hook  | `http://socaas-shuffle-frontend.socaas-soar.svc.cluster.local/api/v1/hooks/webhook_954e33fd-f078-473e-bb9c-96500fa3290f` | Internal K8s DNS only |
| TheHive API (K8s)   | `http://socaas-thehive.socaas-thehive.svc.cluster.local:9000` | Internal K8s DNS only |
| Shuffle Orborus      | `tcp://192.168.122.12:2375`                  | Docker socket for workflow runners  |
| VirusTotal API       | `https://www.virustotal.com/api/v3/`        | External enrichment                  |

---

## 4. Service Ports

| Service                    | Port (NodePort)      | Description                          |
|----------------------------|----------------------|--------------------------------------|
| Wazuh Dashboard            | 5601 (30002)         | OpenSearch Dashboards web UI         |
| Wazuh Agent TCP (Events)   | 1514 (31514)         | OSSEC agent event channel            |
| Wazuh Agent UDP (Syslog)   | 1514 (31516)         | OSSEC agent syslog channel           |
| Wazuh Agent Enrollment     | 1515 (31515)         | Agent registration                   |
| Wazuh Manager API          | 55000 (31550)        | Wazuh management REST API            |
| Shuffle Frontend           | 80 (30080)           | Shuffle web UI                       |
| Shuffle Backend            | 5001                 | Shuffle backend API (internal)       |
| TheHive UI / API           | 9000 (30900)         | TheHive web UI and REST API          |
| Pipeline Gateway           | 8080                 | Alert enrichment and routing         |
| HAProxy Stats              | 8404                 | HAProxy statistics                   |
| Redis                      | 6379                 | Shuffle session/workflow cache       |
| Cassandra                  | 9042                 | TheHive primary database             |
| Elasticsearch (TheHive)    | 9200                 | TheHive index backend                |
| OpenSearch (Shuffle)       | 9200                 | Shuffle search backend               |
| MinIO                      | 9000, 9001           | TheHive file/S3 storage              |
| Wazuh Indexer              | 9200                 | Wazuh alert storage                  |
| Kubernetes API             | 443                  | Cluster management                   |

---

## 5. Authentication Credentials

| Service               | Username                           | Password                        | Notes                           |
|------------------------|------------------------------------|---------------------------------|---------------------------------|
| Wazuh Dashboard        | `admin`                            | `5yr9lkZkpooI84CDPJv2`         | LAB SECRET                      |
| Wazuh API              | `wazuh-wui`                        | `MyS3cr37P450rChangeMe`        | LAB SECRET                      |
| Shuffle Admin          | `admin@socaas.local`               | `DH4GGzUXooZtiCUbNi9G`         | LAB SECRET                      |
| TheHive Admin          | `admin@thehive.local`              | `secret`                        | Default dev password            |
| TheHive Integration    | `socaas-shuffle@thehive.local`     | `shuffle-lab-2026-xyz`         | LAB SECRET — Shuffle↔TheHive   |
| TheHive Analyst        | `socaas-analyst@thehive.local`     | `socaas-analyst-2026`          | Currently locked                |
| TheHive Operator       | `socaas-ops@thehive.local`         | `socaas-ops-2026`              | Active                          |
| TheHive Fresh          | `socaas-fresh@thehive.local`       | `socaas-fresh-2026`            | Test user                       |
| VM SSH                 | `k8s-user`                         | `OkjjOCtBKcpNkxX7r8FG`         | LAB SECRET                      |
| MinIO                  | `thehiveadmin`                     | `gyRkpevNEGTrytD00M9v`         | LAB SECRET                      |

> **Note:** All values above are sourced from `.env`, Kubernetes secrets, and
> deployment configs. TheHive 5.3 uses PBKDF2 password hashing for UI logins.

---

## 6. API Keys & Tokens

| Service            | Key Name                    | Full Value                                                     | Stored In                              |
|--------------------|-----------------------------|----------------------------------------------------------------|----------------------------------------|
| TheHive API        | `THEHIVE_API_KEY`           | `0rMyTHik17a/SdJKZQ4+6sPEbPV7dpPa`                            | `socaas-soar/integration-secrets`      |
| VirusTotal         | `VIRUSTOTAL_API_KEY`        | `495a9b7ecc08efb18eb637a402be923d9dad18c38382dddcdc363fbcd1582410` | `socaas-soar/socaas-pipeline-secrets` |
| Pipeline Shared    | `PIPELINE_SHARED_SECRET`    | `Hu2sjS8pd2CFpWixOYX0`                                        | `socaas-soar/socaas-pipeline-secrets`  |
| TheHive Secret     | `secret`                    | `5nDmjiK8BrUBtuTjQz71`                                        | `socaas-thehive/socaas-thehive-secrets`|
| MinIO Access Key   | `minio-access-key`          | `thehiveadmin`                                                 | `socaas-thehive/socaas-thehive-secrets`|
| MinIO Secret Key   | `minio-secret-key`          | `gyRkpevNEGTrytD00M9v`                                        | `socaas-thehive/socaas-thehive-secrets`|
| Shuffle Webhook URL| `native-shuffle-webhook-url`| `http://socaas-shuffle-frontend.socaas-soar.svc.cluster.local/api/v1/hooks/webhook_954e33fd-sk-edc31ab8674749239ad39d8fafb56e05f078-473e-bb9c-96500fa3290f` | `socaas-soar/socaas-pipeline-secrets` |

---

## 7. Kubernetes Secrets

| Namespace         | Secret Name                    | Purpose                                     |
|--------------------|--------------------------------|---------------------------------------------|
| `socaas-siem`     | `socaas-wazuh-secrets`        | Wazuh admin/api credentials                 |
| `socaas-siem`     | `socaas-pipeline-secrets`     | Shared webhook secret                       |
| `socaas-soar`     | `integration-secrets`         | TheHive API key for Shuffle integration     |
| `socaas-soar`     | `socaas-pipeline-secrets`     | VT API key, TheHive key, shared secret, webhook |
| `socaas-soar`     | `socaas-shuffle-secrets`      | Shuffle admin, OpenSearch credentials       |
| `socaas-thehive`  | `socaas-thehive-secrets`      | TheHive secret, admin API key, MinIO creds  |
| `socaas-system`   | `sh.helm.release.v1.socaas.*` | Helm release state (auto-managed)           |

---

## 8. TheHive Configuration

| Item                          | Value                                             |
|-------------------------------|---------------------------------------------------|
| Current version               | `5.3.11-1`                                         |
| License type                  | Community (trial)                                  |
| Operational organization      | `socaas` (org-admin profile)                       |
| Platform admin organization   | `admin`                                            |
| Integration user              | `socaas-shuffle@thehive.local`                     |
| Integration user type         | Normal                                             |
| Integration user profile      | `org-admin` (in both `socaas` and `admin` orgs)    |
| Default organization          | `socaas`                                           |
| Operational permissions       | `manageCase/*`, `manageAlert/*`, `manageTask`, etc.|

### Required API Header

All operational API calls to TheHive MUST include:

```
X-Organisation: socaas
Authorization: Bearer 0rMyTHik17a/SdJKZQ4+6sPEbPV7dpPa
```

---

## 9. Shuffle Workflow Overview

### Current Pipeline Flow

```
Wazuh Alert → Pipeline Gateway (port 8080 or 30000)
  ├─ Extract observables (IPs, domains, hashes)
  ├─ VirusTotal enrichment (if API key configured)
  ├─ Forward to Shuffle Native Webhook
  └─ Create TheHive Alert (via API)
       ↓
Shuffle Workflow (webhook_954e33fd):
  1. Webhook Receiver
  2. Build_SOC_Telegram_Message
  3. Send_Telegram_Notification
  4. Send_Email_Notification (if configured)
  5. Create_TheHive_Case
  6. Final_Response
```

### Key Integration URLs

| Component               | URL                                                                 |
|-------------------------|---------------------------------------------------------------------|
| Shuffle Native Webhook  | `http://socaas-shuffle-frontend.socaas-soar.svc.cluster.local/api/v1/hooks/webhook_954e33fd-f078-473e-bb9c-96500fa3290f` |
| TheHive API             | `http://192.168.122.1:30900` (external) / `http://socaas-thehive.socaas-thehive.svc.cluster.local:9000` (internal) |
| Wazuh Webhook Endpoint  | `http://192.168.122.1:30000/hooks/wazuh`                            |

### TheHive Integration Headers

```
Authorization: Bearer 0rMyTHik17a/SdJKZQ4+6sPEbPV7dpPa
X-Organisation: socaas
Content-Type: application/json
```

### Telegram Message Variables (Shuffle context path)

| Variable              | JSONPath                                     |
|-----------------------|----------------------------------------------|
| Alert rule            | `${webhook.rule.description}`                |
| Alert level           | `${webhook.rule.level}`                      |
| Agent name            | `${webhook.agent.name}`                      |
| Agent IP              | `${webhook.agent.ip}`                        |
| Observables (IPs)     | `${webhook.enrichment.virustotal.observables.ips}` |
| Observables (domains) | `${webhook.enrichment.virustotal.observables.domains}` |
| Observables (hashes)  | `${webhook.enrichment.virustotal.observables.hashes}` |

### Email Subject/Body Paths (Shuffle context)

| Field       | Path / Template                                                    |
|-------------|--------------------------------------------------------------------|
| Subject     | `SOCaaS Alert: ${webhook.rule.description} - ${webhook.agent.name}`|
| Body        | Formatted from webhook alert JSON including observables and enrichment |

---

## 10. Operational Commands

### Cluster Status

```bash
kubectl get pods -A
kubectl get nodes -o wide
kubectl get svc -A
kubectl logs -n socaas-soar deploy/socaas-pipeline-gateway --tail=100
kubectl logs -n socaas-thehive deploy/socaas-thehive --tail=100
```

### VM Management

```bash
# List all VMs
virsh list --all

# Start VMs in correct order
virsh start k8s-master
sleep 60
virsh start k8s-worker1
virsh start k8s-worker2

# Stop VMs gracefully (reverse order)
virsh shutdown k8s-worker2
virsh shutdown k8s-worker1
virsh shutdown k8s-master

# Force stop if needed
virsh destroy k8s-master
```

### Restart Procedures

```bash
kubectl rollout restart deploy/socaas-pipeline-gateway -n socaas-soar
kubectl rollout restart deploy/socaas-thehive -n socaas-thehive
kubectl rollout restart sts/socaas-wazuh-manager -n socaas-siem
```

### TheHive API Testing

```bash
export THEHIVE_URL="http://192.168.122.1:30900"
export THEHIVE_API_KEY="0rMyTHik17a/SdJKZQ4+6sPEbPV7dpPa"

# Check current user permissions
curl -sS "$THEHIVE_URL/api/v1/user/current" \
  -H "Authorization: Bearer $THEHIVE_API_KEY" \
  -H "X-Organisation: socaas"

# Create test alert
curl -sS -X POST "$THEHIVE_URL/api/v1/alert" \
  -H "Authorization: Bearer $THEHIVE_API_KEY" \
  -H "X-Organisation: socaas" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Alert","description":"API test","type":"test","source":"api","sourceRef":"test-001","severity":2,"tlp":2,"pap":2}'

# Create test case
curl -sS -X POST "$THEHIVE_URL/api/v1/case" \
  -H "Authorization: Bearer $THEHIVE_API_KEY" \
  -H "X-Organisation: socaas" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Case","description":"API test","severity":2,"tlp":2,"pap":2}'
```

### Webhook Test

```bash
curl -sS "http://192.168.122.1:30000/healthz"

curl -sS -X POST "http://192.168.122.1:30000/hooks/wazuh" \
  -H "X-SOCaaS-Webhook-Secret: Hu2sjS8pd2CFpWixOYX0" \
  -H "Content-Type: application/json" \
  -d '{"rule":{"id":"1002","level":5,"description":"Test alert"},"agent":{"id":"000","name":"test-agent","ip":"8.8.8.8"}}'
```

---

## 11. Known Issues / Lessons Learned

### TheHive Admin Organization Trap

TheHive 5.x has a built-in `admin` organization for **platform administration only**.
Cases, alerts, and tasks MUST be created in a non-admin operational organization.

**Symptom:** API calls to `/api/v1/case` or `/api/v1/alert` returning 403 or permission
errors, despite the user having `org-admin` profile.

**Root Cause:** The integration user was only in the `admin` organization, which does
not support operational objects (cases, alerts).

**Fix Applied:**
1. Created a new non-admin organization: `socaas`
2. Bound `socaas-shuffle@thehive.local` to it with `org-admin` profile
3. Set default organization to `socaas`
4. All API calls now use `X-Organisation: socaas` header

### Required: X-Organisation Header

TheHive 5.3 API **requires** the `X-Organisation: socaas` header on every request.
Without it, requests default to `admin` org and fail with permission errors.

### Community License

- The Community license has quota limits (`users.normal: quota=2`).
- The build uses Community (trial) mode.
- Activation step: navigate to `/administration/platform/license` in TheHive UI.
- Normal users consume license quota; consider using service users for
  integration accounts if TheHive edition supports them.

### NetworkPolicies Issue (Fixed)

- Initially, NetworkPolicies blocked inter-namespace traffic.
- Fix: Updated NetworkPolicy YAML to allow required cross-namespace flows
  (e.g., pipeline-gateway → TheHive, pipeline-gateway → Shuffle webhook).

### VM Startup Order

- k8s-master must start first (control-plane)
- k8s-worker1 (SIEM workloads) and k8s-worker2 (SOAR/TheHive workloads) can start
  in parallel after master is Ready
- Allow 2-3 minutes after master boot for API server to become available

---

## 12. Future Improvements

| Item                       | Description                                                     |
|----------------------------|-----------------------------------------------------------------|
| IOC auto-blocking          | Automate IP/hash blocking via firewall/pDNS integration         |
| Analyst approval flow      | Add Shuffle step requiring analyst sign-off before blocking     |
| Email enrichment           | Integrate Mailtrap or real SMTP for alert notifications         |
| Full TheHive automation    | Complete the Shuffle → TheHive workflow for case lifecycle      |
| Multi-tenant support       | Support multiple organizations in TheHive for different clients |
| SOAR playbooks             | Expand Shuffle workflows with more playbooks (phishing, etc.)   |
| Dashboarding               | Build Grafana dashboards for SOC metrics from Wazuh + TheHive   |
| Backup automation          | Automated PVC snapshots and etcd backups                        |
| TLS termination            | Add HTTPS for all services (currently HTTP)                     |
| Service user conversion    | Convert integration accounts to TheHive service users if supported |

---

## References

| Resource              | Path                                                    |
|-----------------------|---------------------------------------------------------|
| Environment file      | `/srv/socaas/SOCaaS_BLUEPRINT_MULTINODE/env/socaas.env` |
| Helm chart            | `/srv/socaas/SOCaaS_BLUEPRINT_MULTINODE/charts/socaas/` |
| Helm values (multinode)| `values-multinode.yaml` (in chart directory)            |
| K8s config            | `~/.kube/config` or `/etc/kubernetes/admin.conf`       |
| VM disk images        | `/var/lib/libvirt/images/socaas/`                       |
| Session log           | `/srv/socaas/session-ses_1f81.md`                       |

---

*Document generated for SOCaaS lab environment. Last update: 2026-05-08.*
