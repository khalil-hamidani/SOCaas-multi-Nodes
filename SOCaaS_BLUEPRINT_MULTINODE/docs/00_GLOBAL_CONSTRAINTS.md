# 00 - Global Constraints

## Locked deployment identity

| Key | Value |
|---|---|
| Deployment mode | Multi-node virtual Kubernetes lab on one physical Parrot OS host |
| Host virtualization | KVM/libvirt default NAT network |
| Host bridge | `virbr0`, `192.168.122.1/24` |
| Kubernetes bootstrap | kubeadm |
| Container runtime | containerd |
| Kubernetes version track | v1.28 |
| CNI | Calico |
| External load balancer | HAProxy on Parrot host, not inside Kubernetes |
| Host storage | Dedicated partition mounted at `/srv/socaas` |
| VM disk storage | qcow2 images under `/srv/socaas/libvirt/images` |
| Kubernetes storage | Static local PVs with nodeAffinity, not HA storage |
| Control-plane workload policy | Control-plane taint kept; no SOC pods on master |

## Hardware budget

The VM plan consumes 20 GB RAM and 10 vCPU before host overhead:

| VM | vCPU | RAM | Disk |
|---|---:|---:|---:|
| k8s-master | 2 | 4 GB | 50 GB |
| k8s-worker1 | 4 | 8 GB | 120 GB |
| k8s-worker2 | 4 | 8 GB | 120 GB |

The host still needs memory for Parrot OS, libvirt, HAProxy, browser, and disk cache. Close heavy applications before deployment.

## Non-negotiable scheduling rules

- `k8s-master` must not run SOC workloads.
- `k8s-worker1` must run SIEM/Wazuh workloads.
- `k8s-worker2` must run SOAR/TheHive/IR workloads.
- Stateful volumes must be pinned to the node that owns the data directory.
- Node selectors, affinity, labels, and PV nodeAffinity must agree.

## Default namespaces

| Namespace | Purpose |
|---|---|
| `socaas-system` | Helm release bookkeeping and shared service accounts |
| `socaas-siem` | Wazuh SIEM components |
| `socaas-soar` | Shuffle SOAR and pipeline gateway |
| `socaas-thehive` | TheHive, Cassandra, MinIO, TheHive Elasticsearch |

## Default passwords

The chart renders credentials as Kubernetes Secrets. The example values are intentionally visible in `values.yaml` so the lab is repeatable, but they must be changed after first login.
