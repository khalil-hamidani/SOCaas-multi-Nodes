# EXECUTION PLAN

This plan is the canonical run order for the multi-node SOCaaS lab. Run every step in sequence and stop on the first failed verification.

## Phase 0 - Prepare variables

```bash
findmnt /srv/socaas
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE
cp env/socaas.env.example env/socaas.env
nano env/socaas.env
bash scripts/00_prepare_socaas_storage.sh
bash scripts/99_verify_storage_layout.sh
```

Do not continue unless `/srv/socaas` is a mounted filesystem. The blueprint writes VM disks to `/srv/socaas/libvirt/images`, downloaded cloud images to `/srv/socaas/downloads`, and generated host artifacts to `/srv/socaas/generated`.

Keep the default IP plan unless your libvirt network differs:

| Host | IP | Purpose |
|---|---|---|
| Parrot host bridge | `192.168.122.1` | HAProxy and VM gateway |
| k8s-master | `192.168.122.10` | control plane only |
| k8s-worker1 | `192.168.122.11` | SIEM/Wazuh workloads |
| k8s-worker2 | `192.168.122.12` | SOAR/TheHive workloads |

## Phase 1 - Host and VM layer

```bash
bash scripts/00_check_host_resources.sh
bash scripts/01_install_kvm_parrot.sh
bash scripts/00_prepare_socaas_storage.sh
bash scripts/02_create_vms.sh
```

Verify:

```bash
virsh list --all
ls -lh /srv/socaas/libvirt/images/*.qcow2
ping -c 2 192.168.122.10
ping -c 2 192.168.122.11
ping -c 2 192.168.122.12
ssh k8s-user@192.168.122.10 hostname
```

## Phase 2 - Kubernetes bootstrap

```bash
bash scripts/03_prepare_all_nodes.sh
bash scripts/04_init_master.sh
bash scripts/05_join_workers_template.sh
bash scripts/06_install_calico.sh
bash scripts/07_label_nodes.sh
```

Verify on the master:

```bash
ssh k8s-user@192.168.122.10 'kubectl get nodes -o wide --show-labels'
```

Expected:

- `k8s-master` is `Ready` with control-plane role and control-plane taint still present
- `k8s-worker1` has `node-role=siem`
- `k8s-worker2` has `node-role=soar`

## Phase 3 - Storage and HAProxy

```bash
bash scripts/08_prepare_worker_storage.sh
bash scripts/09_install_haproxy_host.sh
```

Verify:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
curl -k https://192.168.122.1:6443/version || true
```

The Kubernetes API test may fail until the master API is reachable from HAProxy, but HAProxy configuration validation must pass.

## Phase 4 - Helm and SOCaaS stack

```bash
bash scripts/10_install_helm.sh
bash scripts/11_deploy_socaas.sh
bash scripts/12_verify_cluster.sh
```

Expected workload placement:

| Namespace | Workloads | Node |
|---|---|---|
| `socaas-siem` | Wazuh Manager, Indexer, Dashboard, alert forwarder | `k8s-worker1` only |
| `socaas-soar` | Shuffle frontend/backend/orborus, Redis, OpenSearch, pipeline gateway | `k8s-worker2` only |
| `socaas-thehive` | TheHive, Cassandra, MinIO, TheHive Elasticsearch | `k8s-worker2` only |

## Phase 5 - External agent and pipeline test

Install the Wazuh Agent on the separate laptop using `docs/14_WAZUH_AGENT_SETUP.md`, then run:

```bash
bash scripts/13_test_alert_pipeline.sh
```

The initial deterministic test posts a sample alert to the pipeline gateway. After you create a native Shuffle webhook, set `SOCAAS_NATIVE_SHUFFLE_WEBHOOK_URL` in `env/socaas.env` and redeploy to have the gateway forward to your Shuffle workflow as well.

## Reset and recovery

Use reset only when you intentionally want to tear down the lab.

```bash
bash scripts/99_reset_lab.sh
```

The reset script asks for confirmation and does not remove VM disks unless explicitly requested with `--destroy-vms`.

After any host reboot, run:

```bash
findmnt /srv/socaas
bash scripts/99_verify_storage_layout.sh
sudo virsh net-start default || true
virsh list --all
```
