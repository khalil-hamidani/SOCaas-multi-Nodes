# 20 - Limitations and Migration to Production

## Lab limitations

1. The physical host is still a single failure domain.
2. The libvirt NAT bridge is not a production network design.
3. Local PVs are not real HA storage.
4. Wazuh, Shuffle, and TheHive are single-replica lab deployments.
5. 23 GB usable RAM is tight for JVM/OpenSearch/Cassandra workloads.
6. HAProxy is a single process on the host.
7. Default credentials and self-signed TLS are not production-safe.

## Production migration path

| Lab choice | Production replacement |
|---|---|
| 3 VMs on one laptop | separate physical servers or cloud instances |
| libvirt NAT | routed VLANs or cloud VPC subnets |
| HAProxy on laptop | redundant HAProxy/Keepalived, cloud LB, or MetalLB + ingress |
| local PVs | Longhorn, Ceph/Rook, NFS, or cloud block storage |
| single Wazuh Indexer | multi-node Wazuh Indexer/OpenSearch cluster |
| single Cassandra | multi-node Cassandra cluster |
| default passwords | external secret manager and rotation |
| manual TLS | cert-manager and private CA/ACME |

## How to migrate storage

1. Deploy a production storage class.
2. Snapshot or export lab data.
3. Change `storage.storageClassName` in `values.yaml`.
4. Disable static PV creation with `storage.createStaticPVs=false`.
5. Restore data into the new PVCs.
6. Redeploy the chart.

## How to migrate HAProxy

1. Move HAProxy to a dedicated node pair or managed LB.
2. Point backends to worker node IPs or service LoadBalancer IPs.
3. Enable TLS termination with real certificates.
4. Restrict source IP ranges.
5. Monitor HAProxy health and logs centrally.
