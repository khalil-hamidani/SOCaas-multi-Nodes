# 04 - VM Creation

The recommended script uses Ubuntu 22.04 cloud images and cloud-init, because it is repeatable and avoids manual ISO clicks.

```bash
bash scripts/00_prepare_socaas_storage.sh
bash scripts/02_create_vms.sh
```

The script creates:

- `/srv/socaas/libvirt/images/k8s-master.qcow2`
- `/srv/socaas/libvirt/images/k8s-worker1.qcow2`
- `/srv/socaas/libvirt/images/k8s-worker2.qcow2`

It downloads the Ubuntu cloud image into `/srv/socaas/downloads/images`, stages the libvirt-readable copy at `/var/lib/libvirt/images/socaas/ubuntu-22.04-server-cloudimg-amd64.img`, and writes cloud-init seed files under `/srv/socaas/generated/vms`.

It also injects:

- hostname
- static IP
- SSH user `k8s-user`
- sudo access
- your SSH public key when available

Verify:

```bash
virsh list --all
ls -lh /srv/socaas/libvirt/images/*.qcow2
virsh domifaddr k8s-master || true
ping -c 2 192.168.122.10
ssh k8s-user@192.168.122.10 hostname
```

Fallback manual method:

1. Download Ubuntu Server 22.04 ISO.
2. Create three VMs with the same CPU/RAM/disk sizes.
3. Assign hostnames exactly: `k8s-master`, `k8s-worker1`, `k8s-worker2`.
4. Configure static IPs matching the table.
5. Install OpenSSH Server.
6. Use the same `k8s-user` account.

Do not proceed until all three VMs can be reached by SSH from the Parrot host.
