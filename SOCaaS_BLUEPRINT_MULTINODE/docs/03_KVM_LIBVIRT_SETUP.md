# 03 - KVM/libvirt Setup

Run on the Parrot host:

```bash
bash scripts/01_install_kvm_parrot.sh
```

The script installs:

- `qemu-kvm`
- `libvirt-daemon-system`
- `libvirt-clients`
- `virtinst`
- `virt-manager`
- `bridge-utils`
- `cloud-image-utils`
- `qemu-utils`

It enables the default libvirt NAT network. Verify:

```bash
virsh net-info default
ip addr show virbr0
```

Expected bridge IP:

```text
192.168.122.1/24
```

If `virbr0` is missing, restart libvirt:

```bash
sudo systemctl restart libvirtd || sudo systemctl restart libvirt-daemon
sudo virsh net-start default
sudo virsh net-autostart default
```
