# SOCaaS Infrastructure Overview

> Generated: 2026-05-04 | Helm release: socaas v1.0.0 (revision 9)

---

## 1. Architecture Summary

```text
                            INTERNET / LAN
                                 │
                    Tailscale Overlay (100.x/8)
                                 │
 ┌─────────────────┐     ┌───────┴────────┐     ┌───────────────────┐
 │   Friend Host   │     │    SOC Host    │     │  Victim VM (KVM)  │
 │    (parrot)     │     │  (socaas-main) │     │  (socaas-victim)  │
 │ 192.168.182.201 │     │ 192.168.182.203│     │  192.168.122.41   │
 │ TS: 100.91.78.126│    │ TS:100.75.201.125│    │ TS:100.101.254.110│
 └────────┬────────┘     └───────┬────────┘     └────────┬──────────┘
          │                      │                        │
          │         ┌────────────┴────────────┐           │
          │         │   HAProxy (0.0.0.0)    │           │
          │         │   :6443 :1514 :1515    │           │
          │         │   :55000 :30002 :30080 │◄──────────┘
          │         │        :30900          │  Wazuh Agent
          │         └────────────┬───────────┘  → SOC TS IP :1514
          │                      │
          │         ┌────────────┴───────────────────────────┐
          │         │        Kubernetes Cluster (v1.28)       │
          │         │                                        │
          │         │  ┌──────────────────────────────────┐  │
          │         │  │    k8s-master  192.168.122.10    │  │
          │         │  │    control-plane                  │  │
          │         │  │    (no SOC workloads)             │  │
          │         │  └──────────────────────────────────┘  │
          │         │                                        │
          │         │  ┌──────────────────────────────────┐  │
          │         │  │   k8s-worker1  192.168.122.11    │  │
          │         │  │   node-role=siem                  │  │
          │         │  │   ┌────────────────────────────┐  │  │
          │         │  │   │ Wazuh Manager  (socaas-siem)│  │  │
          │         │  │   │ Wazuh Indexer               │  │  │
          │         │  │   │ Wazuh Dashboard             │  │  │
          │         │  │   └────────────────────────────┘  │  │
          │         │  └──────────────────────────────────┘  │
          │         │                                        │
          │         │  ┌──────────────────────────────────┐  │
          │         │  │   k8s-worker2  192.168.122.12    │  │
          │         │  │   node-role=soar                  │  │
          │         │  │   ┌──────┐ ┌──────────┐ ┌──────┐ │  │
          │         │  │   │Shuffle│ │Pipeline  │ │TheHive│ │  │
          │         │  │   │SOAR   │ │Gateway   │ │ + DBs │ │  │
          │         │  │   └──────┘ └──────────┘ └──────┘ │  │
          │         │  └──────────────────────────────────┘  │
          │         └─────────────────────────────────────────┘

Alert Flow:
  Victim VM activity
    → Wazuh Agent (UDP/TCP :1514 via Tailscale 100.75.201.125)
      → HAProxy :1514
        → socaas-wazuh-manager-nodeport :31514
          → Wazuh Manager pod
            → Pipeline Gateway :8080
              → Shuffle workflow
                → TheHive case
```

---

## 2. Physical / Host Machines

| Name | Owner/Location | LAN IP | Tailscale IP | Role | Access Method | Notes |
|------|---------------|--------|-------------|------|---------------|-------|
| socaas-main | SOC operator | 192.168.182.203 | 100.75.201.125 | SOC host, HAProxy, Tailscale gateway | `ssh khalil@socaas-main` (local) | Runs HAProxy exposing K8s services, libvirt VMs |
| parrot | Friend/partner | 192.168.182.201 | 100.91.78.126 | Victim VM host, KVM/libvirt | `ssh zzenda@100.91.78.126` | Hosts the socaas-victim VM |
| socaas-victim | Friend/partner (VM) | 192.168.122.41 (libvirt NAT) | 100.101.254.110 | Monitored endpoint with Wazuh Agent | `ssh victim@100.101.254.110` | Ubuntu 22.04, 2 vCPU, 2 GiB RAM, 20 GiB disk |

---

## 3. SOC Kubernetes Nodes

| Node | IP | Role | K8s Labels | Runs | Notes |
|------|----|------|-----------|------|-------|
| k8s-master | 192.168.122.10 | control-plane | `node-role.kubernetes.io/control-plane=` | etcd, apiserver, controller-manager, scheduler, coredns, calico | No SOC workloads scheduled here |
| k8s-worker1 | 192.168.122.11 | worker | `node-role=siem, socaas.workload=siem` | Wazuh Manager, Indexer, Dashboard | All SIEM workloads via nodeSelector |
| k8s-worker2 | 192.168.122.12 | worker | `node-role=soar, socaas.workload=soar` | Shuffle, TheHive, Pipeline Gateway, Redis, Cassandra, MinIO, Elasticsearch | All SOAR/IR workloads via nodeSelector |

All nodes: Ubuntu 22.04.5 LTS, Kubernetes v1.28.15, containerd://2.2.1, Calico v3.28.5

---

## 4. Tailscale Inventory

| Machine | Tailscale IP | OS | Role | Used For | Status |
|---------|-------------|----|----|----------|--------|
| socaas-main | 100.75.201.125 | Parrot (Debian) | SOC host | Wazuh API, Dashboard, Shuffle, TheHive, HAProxy ingress | Active |
| parrot | 100.91.78.126 | Parrot (Debian) | Friend host | KVM hypervisor, SSH jump to victim VM | Active |
| socaas-victim | 100.101.254.110 | Ubuntu 22.04 | Victim VM | Wazuh Agent endpoint, test target | Active |

All machines under Tailscale account: `hamidani2002@`

---

## 5. External Access URLs

| Service | URL via SOC host | URL via Tailscale | Protocol | Login Source | Notes |
|---------|-----------------|-------------------|----------|-------------|-------|
| Wazuh Dashboard | http://192.168.182.203:30002 | http://100.75.201.125:30002 | HTTP | `env/socaas.env` → SOCAAS_WAZUH_ADMIN_USER/PASSWORD | Wazuh 4.8.2 |
| Shuffle UI | http://192.168.182.203:30080 | http://100.75.201.125:30080 | HTTP | `env/socaas.env` → SOCAAS_SHUFFLE_ADMIN_PASSWORD | SOAR automation |
| TheHive UI | http://192.168.182.203:30900 | http://100.75.201.125:30900 | HTTP | Pending API key config | Case management |
| Wazuh Agent Events | 192.168.182.203:1514 | 100.75.201.125:1514 | TCP/UDP | N/A (agent auth) | Agent → Manager event channel |
| Wazuh Agent Enrollment | 192.168.182.203:1515 | 100.75.201.125:1515 | TCP | N/A (agent auth) | Agent registration |
| Wazuh API | 192.168.182.203:55000 | 100.75.201.125:55000 | HTTPS | Kubernetes secret `socaas-wazuh-secrets` | Manager REST API |
| Kubernetes API | 192.168.182.203:6443 | — | HTTPS | K8s kubeconfig | Proxied via HAProxy |

---

## 6. Kubernetes Namespaces

| Namespace | Purpose | Main Components |
|-----------|---------|-----------------|
| socaas-system | Helm release metadata | Helm secrets, release info |
| socaas-siem | Wazuh SIEM stack | Wazuh Manager, Indexer, Dashboard |
| socaas-soar | SOAR / pipeline | Shuffle, Pipeline Gateway, Redis, OpenSearch |
| socaas-thehive | Incident Response | TheHive, Cassandra, MinIO, Elasticsearch |
| kube-system | Kubernetes core | coredns, calico, etcd, apiserver, kube-proxy |
| default | Unused | Empty |

---

## 7. SOC Services / Kubernetes Services

### Wazuh SIEM (socaas-siem)

| Service | Type | Cluster IP | Ports | External Port | Role |
|---------|------|-----------|-------|---------------|------|
| socaas-wazuh-manager | ClusterIP | 10.98.119.232 | 1514/TCP, 1514/UDP, 1515/TCP, 55000/TCP | — | Internal manager access |
| socaas-wazuh-manager-nodeport | NodePort | 10.104.116.91 | 1514,1515,55000 | 31514,31515,31550 | HAProxy → NodePort forwarding |
| socaas-wazuh-indexer | ClusterIP | 10.99.53.228 | 9200/TCP | — | Wazuh Indexer (OpenSearch fork) |
| socaas-wazuh-dashboard | NodePort | 10.98.125.244 | 5601/TCP | 30002/TCP | Wazuh Web UI |

### SOAR / Pipeline (socaas-soar)

| Service | Type | Cluster IP | Ports | External Port | Role |
|---------|------|-----------|-------|---------------|------|
| socaas-pipeline-gateway | ClusterIP | 10.99.57.196 | 8080/TCP | — | Alert ingestion from Wazuh |
| socaas-redis | ClusterIP | 10.96.17.16 | 6379/TCP | — | Shuffle message queue |
| socaas-shuffle-backend | ClusterIP | 10.104.153.174 | 5001/TCP | — | Shuffle workflow engine |
| socaas-shuffle-frontend | NodePort | 10.107.175.241 | 80/TCP | 30080/TCP | Shuffle Web UI |
| socaas-shuffle-opensearch | ClusterIP | 10.107.25.203 | 9200/TCP | — | Shuffle search index |

### Incident Response (socaas-thehive)

| Service | Type | Cluster IP | Ports | External Port | Role |
|---------|------|-----------|-------|---------------|------|
| socaas-thehive | NodePort | 10.97.197.56 | 9000/TCP | 30900/TCP | TheHive Web UI / API |
| socaas-cassandra | ClusterIP | 10.105.237.212 | 9042/TCP | — | TheHive database |
| socaas-minio | ClusterIP | 10.99.139.215 | 9000/TCP, 9001/TCP | — | TheHive file/attachment storage |
| socaas-thehive-elasticsearch | ClusterIP | 10.109.144.123 | 9200/TCP | — | TheHive full-text search |

---

## 8. Pods and Workloads

### Wazuh SIEM (worker1 — node-role=siem)

| Namespace | Workload | Type | Pod(s) | Pod IP | Ready | Role |
|-----------|----------|------|--------|--------|-------|------|
| socaas-siem | socaas-wazuh-manager | StatefulSet | socaas-wazuh-manager-0 | 10.244.194.101 | 2/2 | Manager + alert-forwarder sidecar |
| socaas-siem | socaas-wazuh-indexer | StatefulSet | socaas-wazuh-indexer-0 | 10.244.194.102 | 1/1 | Alert indexing and storage |
| socaas-siem | socaas-wazuh-dashboard | Deployment | socaas-wazuh-dashboard-* | 10.244.194.109 | 1/1 | Wazuh Web UI (OpenSearch Dashboards + plugin) |

### SOAR / Pipeline (worker2 — node-role=soar)

| Namespace | Workload | Type | Pod(s) | Pod IP | Ready | Role |
|-----------|----------|------|--------|--------|-------|------|
| socaas-soar | socaas-pipeline-gateway | Deployment | socaas-pipeline-gateway-* | 10.244.126.7 | 1/1 | Alert webhook receiver |
| socaas-soar | socaas-redis | Deployment | socaas-redis-* | 10.244.126.25 | 1/1 | Shuffle queue/cache |
| socaas-soar | socaas-shuffle-backend | Deployment | socaas-shuffle-backend-* | 10.244.126.33 | 1/1 | Shuffle workflow engine |
| socaas-soar | socaas-shuffle-frontend | Deployment | socaas-shuffle-frontend-* | 10.244.126.30 | 1/1 | Shuffle Web UI |
| socaas-soar | socaas-shuffle-opensearch | StatefulSet | socaas-shuffle-opensearch-0 | 10.244.126.9 | 1/1 | Shuffle search backend |
| socaas-soar | socaas-shuffle-orborus | Deployment | socaas-shuffle-orborus-* | 10.244.126.8 | 1/1 | Shuffle scheduler |

### Incident Response (worker2 — node-role=soar)

| Namespace | Workload | Type | Pod(s) | Pod IP | Ready | Role |
|-----------|----------|------|--------|--------|-------|------|
| socaas-thehive | socaas-thehive | Deployment | socaas-thehive-* | 10.244.126.28 | 1/1 | TheHive application |
| socaas-thehive | socaas-cassandra | StatefulSet | socaas-cassandra-0 | 10.244.126.18 | 1/1 | TheHive main database |
| socaas-thehive | socaas-minio | StatefulSet | socaas-minio-0 | 10.244.126.12 | 1/1 | File storage for TheHive |
| socaas-thehive | socaas-thehive-elasticsearch | StatefulSet | socaas-thehive-elasticsearch-0 | 10.244.126.11 | 1/1 | TheHive search engine |

---

## 9. Storage Mapping

| PV | PVC | Namespace | Size | Used By | Reclaim Policy |
|----|-----|-----------|------|---------|----------------|
| socaas-pv-wazuh-manager | wazuh-manager-pvc | socaas-siem | 10 Gi | Wazuh Manager (alerts, logs, config) | Retain |
| socaas-pv-wazuh-indexer | wazuh-indexer-pvc | socaas-siem | 18 Gi | Wazuh Indexer (alert indices) | Retain |
| socaas-pv-wazuh-dashboard | wazuh-dashboard-pvc | socaas-siem | 3 Gi | Dashboard (plugin config, saved objects) | Retain |
| socaas-pv-shuffle-backend | shuffle-backend-pvc | socaas-soar | 3 Gi | Shuffle Backend | Retain |
| socaas-pv-shuffle-opensearch | shuffle-opensearch-pvc | socaas-soar | 8 Gi | Shuffle OpenSearch | Retain |
| socaas-pv-redis | redis-pvc | socaas-soar | 1 Gi | Shuffle Redis | Retain |
| socaas-pv-thehive | thehive-pvc | socaas-thehive | 4 Gi | TheHive application data | Retain |
| socaas-pv-cassandra | cassandra-pvc | socaas-thehive | 15 Gi | TheHive Cassandra DB | Retain |
| socaas-pv-minio | minio-pvc | socaas-thehive | 8 Gi | TheHive MinIO file storage | Retain |
| socaas-pv-thehive-es | thehive-elasticsearch-pvc | socaas-thehive | 15 Gi | TheHive Elasticsearch | Retain |

**Total allocated:** ~85 Gi | **StorageClass:** `socaas-local` | **Access Mode:** ReadWriteOnce

All PVs are local-hostpath based, bound to `/var/socaas/storage/...` on their respective worker nodes.

---

## 10. Wazuh Agent Inventory

| Agent ID | Agent Name | Hostname | Libvirt IP | Tailscale IP | Status | Manager Address | Notes |
|----------|-----------|----------|-----------|-------------|--------|----------------|-------|
| 000 | socaas-wazuh-manager-0 (server) | — | 127.0.0.1 | — | Active/Local | localhost | Built-in manager self-agent |
| 001 | friend-victim-01 | socaas-victim | 192.168.122.41 | 100.101.254.110 | Active | 100.75.201.125 (Tailscale) | Ubuntu 22.04 VM on friend KVM, Wazuh 4.8.2 |

Agent `friend-victim-01` connects to the SOC Wazuh Manager via Tailscale IP `100.75.201.125:1514`. The Tailscale overlay eliminates the need to update the manager address when LAN IPs change.

---

## 11. Network Flow Table

| Source | Destination | Port | Protocol | Purpose | Path |
|--------|-------------|------|----------|---------|------|
| Victim VM (Wazuh Agent) | SOC host (HAProxy) | 1514 | TCP | Agent event forwarding | Tailscale → HAProxy → NodePort 31514 → Manager pod |
| Victim VM (Wazuh Agent) | SOC host (HAProxy) | 1515 | TCP | Agent enrollment | Tailscale → HAProxy → NodePort 31515 → Manager pod |
| Wazuh Dashboard pod | socaas-wazuh-manager | 55000 | HTTPS | Dashboard API queries | Internal K8s service |
| Wazuh Manager pod | Pipeline Gateway | 8080 | HTTP | Alert forwarding for SOAR | Internal K8s service (NetworkPolicy restricted) |
| Pipeline Gateway | Shuffle Backend | 5001 | HTTP | Trigger workflow | Internal K8s service |
| User browser | SOC host (HAProxy) | 30002 | HTTP | Wazuh Dashboard UI | HAProxy → NodePort 30002 → Dashboard pod |
| User browser | SOC host (HAProxy) | 30080 | HTTP | Shuffle UI | HAProxy → NodePort 30080 → Shuffle frontend pod |
| User browser | SOC host (HAProxy) | 30900 | HTTP | TheHive UI | HAProxy → NodePort 30900 → TheHive pod |
| SOC operator | k8s-master | 6443 | HTTPS | kubectl / K8s API | HAProxy proxy |

---

## 12. Credentials and Secret Locations

| Credential | Stored In | Used By | Notes |
|-----------|----------|---------|-------|
| Wazuh admin credentials | `env/socaas.env` (admin user) + `socaas-wazuh-secrets` K8s secret | Wazuh Dashboard login | User: admin |
| Wazuh API credentials | `socaas-wazuh-secrets` (api-user, api-password) | Dashboard → Manager API | Used in dashboard plugin config (wazuh.yml) |
| Shuffle admin credentials | `env/socaas.env` → SOCAAS_SHUFFLE_ADMIN_PASSWORD | Shuffle UI login | |
| TheHive credentials | Pending configuration | TheHive UI/API | API key not yet configured |
| Pipeline Gateway webhook secret | `socaas-pipeline-shared-secret` | Wazuh Manager → Pipeline Gateway shared auth | |
| VirusTotal API key | Pending | Shuffle enrichment workflow | Not yet configured |
| Tailscale auth | Managed by Tailscale account (hamidani2002@) | All three Tailscale machines | |
| Friend host SSH | SSH key on SOC host | Admin access to friend host | `id_ed25519_victim` key |
| Victim VM SSH | SSH key in friend host | Admin access to victim VM | `id_ed25519_victim` key; password backup: victim/victim |

**Do not store plaintext passwords in this document. Always reference the secret source.**

---

## 13. Current Health Checklist

Status as of 2026-05-04:

- [x] Helm release socaas deployed
- [x] All SOC pods Running (13/13)
- [x] Wazuh Dashboard loads (302 → login)
- [x] Wazuh API connection healthy (405 Method Not Allowed on root = reachable)
- [x] friend-victim-01 Active (Agent ID 001)
- [x] Wazuh alerts visible (sudo, SSH, SCA events flowing)
- [x] Shuffle UI reachable (200 OK)
- [x] TheHive UI reachable (AuthenticationError on API = running)
- [x] Tailscale all machines connected (3/3)
- [x] Calico NetworkPolicies active (12 policies across 3 namespaces)
- [x] No pod bad states (CrashLoop, ImagePull, Init, Pending)

---

## 14. Network Policies Summary

| Namespace | Policy | Effect |
|-----------|--------|--------|
| socaas-siem | socaas-default-deny-siem | Deny all ingress by default |
| socaas-siem | socaas-allow-dns-siem | Allow DNS queries |
| socaas-siem | socaas-allow-siem-internal | Allow SIEM pod-to-pod communication |
| socaas-siem | socaas-allow-wazuh-ingress | Allow external → Wazuh Manager (1514/1515/55000) |
| socaas-siem | socaas-allow-wazuh-dashboard-ingress | Allow external → Dashboard (5601) |
| socaas-siem | socaas-allow-wazuh-to-pipeline | Allow Manager → Pipeline Gateway |
| socaas-soar | socaas-default-deny-soar | Deny all ingress by default |
| socaas-soar | socaas-allow-dns-soar | Allow DNS queries |
| socaas-soar | socaas-allow-soar-internal-and-ui | Allow SOAR internal + UI ingress |
| socaas-thehive | socaas-default-deny-ir | Deny all ingress by default |
| socaas-thehive | socaas-allow-dns-ir | Allow DNS queries |
| socaas-thehive | socaas-allow-ir-internal-and-ui | Allow IR internal + UI ingress |

---

## 15. Common Commands

```bash
# ===== SOC HEALTH =====
# Check all SOC pods
ssh k8s-user@192.168.122.10 'kubectl get pods -A -o wide | grep socaas'

# Check for bad pod states
ssh k8s-user@192.168.122.10 'kubectl get pods -A | grep -E "CrashLoop|ImagePull|Init|Pending|ContainerCreating"'

# ===== WAZUH AGENTS =====
# List all agents
ssh k8s-user@192.168.122.10 'kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l'

# Check agent alerts
ssh k8s-user@192.168.122.10 'kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- sh -c "tail -n 100 /var/ossec/logs/alerts/alerts.json | grep friend-victim"'

# ===== TAILSCALE =====
# Show all peers and status
tailscale status

# Ping friend host via Tailscale
tailscale ping 100.91.78.126

# ===== REMOTE ACCESS =====
# SSH to friend host (via Tailscale)
ssh zzenda@100.91.78.126

# SSH to victim VM (via Tailscale)
ssh victim@100.101.254.110

# SSH to victim VM via friend jump
ssh -J zzenda@100.91.78.126 victim@192.168.122.41

# ===== VICTIM VM WAZUH =====
# Check agent status
ssh victim@100.101.254.110 'systemctl is-active wazuh-agent'

# Restart agent
ssh victim@100.101.254.110 'sudo systemctl restart wazuh-agent && sudo tail -n 50 /var/ossec/logs/ossec.log'

# Verify agent config
ssh victim@100.101.254.110 'grep "<address>" /var/ossec/etc/ossec.conf'

# Generate test event
ssh victim@100.101.254.110 'logger "SOCaaS test event $(date)"'

# ===== FRIEND HOST VM MANAGEMENT =====
# List VMs
ssh zzenda@100.91.78.126 'virsh -c qemu:///system list --all'

# Check VM IP
ssh zzenda@100.91.78.126 'virsh -c qemu:///system domifaddr socaas-victim'

# ===== DASHBOARD URLS =====
# http://100.75.201.125:30002   Wazuh Dashboard
# http://100.75.201.125:30080   Shuffle
# http://100.75.201.125:30900   TheHive

# ===== TAILSCALE IP UPDATE SCRIPT =====
# If Tailscale IPs change, edit variables in:
# /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE/scripts/phase5_use_tailscale_for_friend_endpoint.sh

# ===== KUBERNETES =====
# Full inventory
ssh k8s-user@192.168.122.10 'kubectl get all -A'

# Pod logs
ssh k8s-user@192.168.122.10 'kubectl logs -n socaas-siem deploy/socaas-wazuh-dashboard --tail=100'
```

---

## 16. Scripts Reference

| Script | Purpose | Location |
|--------|---------|----------|
| phase5_update_friend_endpoint_ips.sh | Update Wazuh agent when LAN IPs change | `scripts/` |
| phase5_use_tailscale_for_friend_endpoint.sh | Reconfigure agent to use Tailscale IP | `scripts/` |
| 13_test_alert_pipeline.sh | Test Wazuh → Pipeline Gateway alert flow | `scripts/` |

---
*End of SOCaaS Infrastructure Overview*
