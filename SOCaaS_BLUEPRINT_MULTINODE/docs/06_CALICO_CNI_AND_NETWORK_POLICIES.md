# 06 - Calico CNI and Network Policies

Install Calico:

```bash
bash scripts/06_install_calico.sh
```

The script patches the Calico manifest so `CALICO_IPV4POOL_CIDR` matches `SOCAAS_POD_CIDR` from `env/socaas.env`. The default lab value is `10.244.0.0/16`, matching kubeadm.

Verify:

```bash
ssh k8s-user@192.168.122.10 'kubectl get pods -n kube-system | grep -E "calico|tigera"'
ssh k8s-user@192.168.122.10 'kubectl get nodes'
ssh k8s-user@192.168.122.10 'kubectl get ippools.crd.projectcalico.org default-ipv4-ippool -o jsonpath="{.spec.cidr}"; echo'
```

The Helm chart includes standard Kubernetes `NetworkPolicy` resources enforced by Calico:

- default deny ingress and egress in SOC namespaces;
- DNS egress to kube-dns;
- Wazuh manager ingress for agent/event/API ports;
- Wazuh manager/forwarder egress to the pipeline gateway;
- Shuffle egress to TheHive API;
- TheHive egress to Cassandra, Elasticsearch, and MinIO;
- UI access from the host bridge and lab subnet.

Apply manifest examples without Helm if needed:

```bash
kubectl apply -f manifests/networkpolicies/calico-baseline.yaml
```

Troubleshooting:

```bash
kubectl describe networkpolicy -n socaas-siem
kubectl get pods -A -o wide
kubectl run netshoot -n socaas-soar --rm -it --image=nicolaka/netshoot -- /bin/bash
```
