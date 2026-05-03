# 02 - Hardware and VM Plan

## Host

| Item | Value |
|---|---|
| OS | Parrot OS |
| RAM | 25 GB physical, about 23 GB usable target |
| CPU | 10 cores/threads allocated to VMs |
| Disk | Dedicated SOCaaS partition mounted at `/srv/socaas` |
| Virtualization | KVM/libvirt |
| Load balancer | HAProxy installed directly on Parrot host |

## VM allocation

| VM | Hostname | IP | vCPU | RAM | Disk | Workload role |
|---|---|---|---:|---:|---:|---|
| VM1 | `k8s-master` | `192.168.122.10` | 2 | 4 GB | 50 GB | Kubernetes control plane only |
| VM2 | `k8s-worker1` | `192.168.122.11` | 4 | 8 GB | 120 GB | SIEM/Wazuh |
| VM3 | `k8s-worker2` | `192.168.122.12` | 4 | 8 GB | 120 GB | SOAR/TheHive/IR |

The qcow2 disks for these VMs are stored on the host at `/srv/socaas/libvirt/images`.

## Resource tuning

The Helm chart requests less than the full VM memory so kube-system, containerd, page cache, and spikes have room. Low-resource mode is enabled in `values-multinode.yaml`:

- Wazuh Indexer heap is reduced.
- TheHive JVM heap is reduced.
- Cassandra heap is reduced.
- Shuffle worker count defaults to one.
- Heavy dependencies are single replicas.

This is enough for a thesis lab, not for production alert volume.
