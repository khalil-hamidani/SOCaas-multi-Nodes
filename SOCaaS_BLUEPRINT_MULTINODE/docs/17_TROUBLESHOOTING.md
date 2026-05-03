# 17 - Troubleshooting

## VM not reachable

```bash
virsh list --all
virsh console k8s-master
virsh domifaddr k8s-master
ip addr show virbr0
sudo virsh net-dhcp-leases default
```

If cloud-init failed, inspect:

```bash
ssh k8s-user@192.168.122.10 'sudo journalctl -u cloud-init --no-pager | tail -100'
```

## Kubernetes node NotReady

```bash
kubectl describe node k8s-worker1
kubectl get pods -n kube-system -o wide
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100
```

Check containerd:

```bash
sudo systemctl status containerd kubelet --no-pager
sudo crictl info | head
```

## Pod Pending

```bash
kubectl describe pod -n <namespace> <pod>
kubectl get pv,pvc -A
kubectl get nodes --show-labels
```

Common causes:

- node label missing;
- local PV nodeAffinity points to wrong host;
- storage directory missing on the worker;
- resource requests too high.

## CrashLoopBackOff

```bash
kubectl logs -n <namespace> <pod> --previous
kubectl describe pod -n <namespace> <pod>
```

For JVM components, reduce heaps in `values-multinode.yaml`.

## HAProxy failure

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl status haproxy --no-pager
sudo journalctl -u haproxy -n 100 --no-pager
sudo ss -tlnp | grep haproxy
```

## NetworkPolicy blocked traffic

Temporarily inspect from a debug pod:

```bash
kubectl apply -f manifests/debug/netshoot.yaml
kubectl exec -it -n socaas-soar netshoot -- bash
```

Do not delete default-deny policies permanently; fix the allow rule selectors instead.
