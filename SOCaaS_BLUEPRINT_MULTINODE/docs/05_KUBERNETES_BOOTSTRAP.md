# 05 - Kubernetes Bootstrap

## Prepare all nodes

```bash
bash scripts/03_prepare_all_nodes.sh
```

This disables swap, enables kernel modules, sets sysctls, installs containerd, and installs kubeadm/kubelet/kubectl from the v1.28 package track.

## Initialize the master

```bash
bash scripts/04_init_master.sh
```

The script runs kubeadm init on `k8s-master` with:

```bash
--apiserver-advertise-address=192.168.122.10
--pod-network-cidr=10.244.0.0/16
--service-cidr=10.96.0.0/12
```

The control-plane taint is intentionally kept.

## Join workers

```bash
bash scripts/05_join_workers_template.sh
```

Verify:

```bash
ssh k8s-user@192.168.122.10 'kubectl get nodes -o wide'
```

Before Calico, nodes may be `NotReady`. After Calico, all nodes should become `Ready`.

## Reset recovery

On a node that failed during bootstrap:

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet /var/lib/etcd
sudo systemctl restart containerd kubelet
```

Then rerun the relevant init or join step.
