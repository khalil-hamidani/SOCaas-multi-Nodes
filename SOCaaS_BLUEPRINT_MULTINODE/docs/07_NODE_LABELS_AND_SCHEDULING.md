# 07 - Node Labels and Scheduling

Run:

```bash
bash scripts/07_label_nodes.sh
```

Labels applied:

```bash
kubectl label node k8s-worker1 node-role=siem socaas.workload=siem --overwrite
kubectl label node k8s-worker2 node-role=soar socaas.workload=soar --overwrite
```

The master is verified for this taint:

```text
node-role.kubernetes.io/control-plane:NoSchedule
```

The Helm chart uses both `nodeSelector` and required node affinity:

- SIEM pods: `node-role=siem`
- SOAR/IR pods: `node-role=soar`

Verification:

```bash
kubectl get pods -A -o wide | grep socaas
kubectl get pods -A -o wide | grep k8s-master && echo "ERROR: SOC pod on master" || echo "OK"
```

If a SOC pod schedules on the master, stop and fix labels/taints before continuing.
