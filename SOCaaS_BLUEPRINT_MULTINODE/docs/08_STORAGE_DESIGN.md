# 08 - Storage Design

## Lab storage model

The Parrot host must have the dedicated storage partition mounted at `/srv/socaas` before deployment. Host-side VM disks are created directly in `/srv/socaas/libvirt/images`, so Kubernetes and containerd data live inside those VM disks instead of on the host root filesystem.

This repository uses static local PersistentVolumes inside the worker VMs. Each PV has `nodeAffinity`, so Kubernetes will only bind and mount it on the intended worker node.

This is correct for a constrained lab, but it is not high availability. If `k8s-worker1` is deleted, Wazuh data on its local disk is unavailable. If `k8s-worker2` is deleted, Shuffle/TheHive data is unavailable.

Host paths and VM paths are intentionally separate:

- Host `/srv/socaas/libvirt/images`: qcow2 disks for `k8s-master`, `k8s-worker1`, and `k8s-worker2`.
- VM `/srv/socaas`: local PV directories used by SOC workloads inside the Kubernetes worker nodes.

## Directories

Create directories with:

```bash
bash scripts/00_prepare_socaas_storage.sh
bash scripts/08_prepare_worker_storage.sh
```

Worker1:

```text
/srv/socaas/wazuh/indexer
/srv/socaas/wazuh/manager
/srv/socaas/wazuh/dashboard
```

Worker2:

```text
/srv/socaas/shuffle/backend
/srv/socaas/shuffle/opensearch
/srv/socaas/shuffle/redis
/srv/socaas/thehive/app
/srv/socaas/thehive/elasticsearch
/srv/socaas/cassandra
/srv/socaas/minio
```

## PV/PVC mapping

| PVC | Namespace | PV path | Node |
|---|---|---|---|
| `wazuh-indexer-pvc` | `socaas-siem` | `/srv/socaas/wazuh/indexer` | worker1 |
| `wazuh-manager-pvc` | `socaas-siem` | `/srv/socaas/wazuh/manager` | worker1 |
| `wazuh-dashboard-pvc` | `socaas-siem` | `/srv/socaas/wazuh/dashboard` | worker1 |
| `shuffle-backend-pvc` | `socaas-soar` | `/srv/socaas/shuffle/backend` | worker2 |
| `shuffle-opensearch-pvc` | `socaas-soar` | `/srv/socaas/shuffle/opensearch` | worker2 |
| `redis-pvc` | `socaas-soar` | `/srv/socaas/shuffle/redis` | worker2 |
| `thehive-pvc` | `socaas-thehive` | `/srv/socaas/thehive/app` | worker2 |
| `thehive-es-pvc` | `socaas-thehive` | `/srv/socaas/thehive/elasticsearch` | worker2 |
| `cassandra-pvc` | `socaas-thehive` | `/srv/socaas/cassandra` | worker2 |
| `minio-pvc` | `socaas-thehive` | `/srv/socaas/minio` | worker2 |

## Migration path

For production, replace local PVs with one of these:

- NFS for simple lab-grade shared storage;
- Longhorn for lightweight replicated block storage;
- Rook/Ceph for a more realistic cloud-native storage layer;
- managed block volumes in a cloud environment.

When migrating, remove the static PV templates and set `storageClassName` to the production storage class in `values.yaml`.
