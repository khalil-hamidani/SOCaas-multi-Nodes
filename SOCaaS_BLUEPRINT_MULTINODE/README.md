# SOCaaS_BLUEPRINT_MULTINODE

This repository is a complete multi-node SOC-as-a-Service lab blueprint for a final-year/thesis project. It replaces the older single-node/hybrid blueprint with a true three-VM Kubernetes design running on one Parrot OS physical host.

The lab topology is:

```text
Parrot OS physical host
  - KVM/libvirt default NAT bridge: 192.168.122.1
  - HAProxy entrypoint for Kubernetes API, Wazuh, Shuffle, TheHive, and stats
  - 25 GB RAM, 10 CPU cores, 300 GB SSD
  - Dedicated SOCaaS storage mounted at /srv/socaas

KVM virtual Kubernetes cluster
  - k8s-master  192.168.122.10  2 vCPU  4 GB RAM    50 GB disk  control-plane only
  - k8s-worker1 192.168.122.11  4 vCPU  8 GB RAM   120 GB disk  SIEM/Wazuh node
  - k8s-worker2 192.168.122.12  4 vCPU  8 GB RAM   120 GB disk  SOAR/TheHive node

External monitored endpoint
  - Separate laptop running Wazuh Agent
  - Connects to Parrot host HAProxy at 192.168.122.1:1514/1515 or compatibility port 30000
```

## What this blueprint fixes

The uploaded execution guide already targets KVM, three Ubuntu VMs, Kubernetes, Calico, HAProxy, Helm, Wazuh, Shuffle, TheHive, and a separate Wazuh agent endpoint. This repository keeps that thesis direction but corrects the parts that commonly break in a real deployment:

- control-plane taint is preserved; no SOC workload is allowed on `k8s-master`
- worker labels are enforced with `node-role=siem` and `node-role=soar`
- all stateful storage uses local PersistentVolumes with `nodeAffinity`
- Helm values use consistent paths under `.Values.global`, `.Values.scheduling`, `.Values.wazuh`, `.Values.shuffle`, `.Values.thehive`, and `.Values.pipeline`
- service selectors match pod labels
- network policies select labels that actually exist
- default-deny policies are included with explicit allow rules
- resource requests are tuned for the available RAM
- scripts do not silently destroy data
- VM disks, downloaded images, generated files, backups, logs, and runtime files are kept under `/srv/socaas`

## Repository layout

```text
SOCaaS_BLUEPRINT_MULTINODE/
  README.md
  EXECUTION_PLAN.md
  env/socaas.env.example
  docs/
  scripts/
  charts/socaas/
  manifests/
  tools/
```

## Fast start

Run from the Parrot host unless a step says it runs on a VM or endpoint.

```bash
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE
cp env/socaas.env.example env/socaas.env

bash scripts/00_prepare_socaas_storage.sh
bash scripts/00_check_host_resources.sh
bash scripts/01_install_kvm_parrot.sh
bash scripts/02_create_vms.sh
bash scripts/03_prepare_all_nodes.sh
bash scripts/04_init_master.sh
bash scripts/05_join_workers_template.sh
bash scripts/06_install_calico.sh
bash scripts/07_label_nodes.sh
bash scripts/08_prepare_worker_storage.sh
bash scripts/09_install_haproxy_host.sh
bash scripts/10_install_helm.sh
bash scripts/11_deploy_socaas.sh
bash scripts/12_verify_cluster.sh
bash scripts/13_test_alert_pipeline.sh
bash scripts/99_verify_storage_layout.sh
```

## Storage model

`/srv/socaas` must be mounted before deployment. The host-side layout is:

```text
/srv/socaas/repo
/srv/socaas/libvirt/images
/srv/socaas/downloads
/srv/socaas/generated
/srv/socaas/backups
/srv/socaas/logs
/srv/socaas/runtime
```

The VM qcow2 disks are created directly in `/srv/socaas/libvirt/images`; the blueprint does not depend on `/var/lib/libvirt/images` or `/src/socaas`. Downloaded cloud images are stored in `/srv/socaas/downloads`, and generated cloud-init/admin files are stored in `/srv/socaas/generated`.

Container images and Kubernetes runtime data live inside the VM disks. SOC application data uses local PersistentVolumes at `/srv/socaas/...` inside the worker VMs, so it also consumes the VM disks stored on the host under `/srv/socaas/libvirt/images`.

After reboot, verify the storage mount before starting VMs or rerunning deployment scripts:

```bash
findmnt /srv/socaas
bash scripts/99_verify_storage_layout.sh
virsh list --all
```

## Access URLs

| Component | URL |
|---|---|
| Kubernetes API | `https://192.168.122.1:6443` |
| HAProxy stats | `http://192.168.122.1:8404/stats` |
| Wazuh Dashboard | `https://192.168.122.1:30002` |
| Shuffle UI | `http://192.168.122.1:30080` |
| TheHive UI | `http://192.168.122.1:30900` |
| Wazuh Agent TCP events | `192.168.122.1:1514` |
| Wazuh Agent enrollment | `192.168.122.1:1515` |
| Wazuh API | `https://192.168.122.1:55000` |
| Wazuh Manager compatibility port | `192.168.122.1:30000` |

## Important limits

This is a multi-node virtual lab, not a production HA platform. It improves thesis alignment by separating control-plane, SIEM, and SOAR/IR workloads, but the physical Parrot laptop remains one failure domain. Local PVs are pinned to worker nodes and are not replicated. Production should use separate physical/cloud nodes, a real load balancer, TLS automation, and distributed storage such as Longhorn, Ceph, NFS, or managed block storage.
