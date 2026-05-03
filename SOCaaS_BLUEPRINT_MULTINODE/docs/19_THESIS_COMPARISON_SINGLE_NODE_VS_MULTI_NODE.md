# 19 - Thesis Comparison: Single Node vs Multi Node

## Old single-node/hybrid pattern

The earlier blueprint placed Kubernetes and many SOC services on one host, sometimes with host containers for stateful services. That design is easier to run but weak for a thesis that claims multi-node SOCaaS orchestration.

Limitations:

- control plane and workloads share one node;
- scheduling controls are not meaningfully demonstrated;
- local storage is not tied to worker roles;
- HAProxy may be a pod rather than an external platform entrypoint;
- the design does not show SIEM/SOAR separation.

## New multi-node virtual pattern

This blueprint uses one physical Parrot host but three Ubuntu VMs:

| Layer | Node | Workload |
|---|---|---|
| Control plane | `k8s-master` | Kubernetes API, scheduler, controller, etcd |
| SIEM | `k8s-worker1` | Wazuh Manager, Indexer, Dashboard |
| SOAR/IR | `k8s-worker2` | Shuffle, Redis, OpenSearch, TheHive, Cassandra, MinIO |

Improvements:

- master isolation matches a real cluster pattern;
- workers have clear security roles;
- Calico policies demonstrate segmentation;
- local PV nodeAffinity demonstrates correct stateful scheduling;
- HAProxy on the host represents an external access layer;
- the external Wazuh Agent laptop demonstrates telemetry ingestion.

## Honest thesis wording

Use this phrase in the thesis:

> The implementation is a multi-node virtual Kubernetes lab hosted on a single physical Parrot OS machine. It demonstrates control-plane isolation, role-based worker scheduling, network segmentation, and SOC alert flow, but the physical host and local storage remain single failure domains.
