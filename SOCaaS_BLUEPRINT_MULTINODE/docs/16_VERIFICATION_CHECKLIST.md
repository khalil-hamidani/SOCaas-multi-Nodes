# 16 - Verification Checklist

## Cluster

```bash
kubectl get nodes -o wide --show-labels
kubectl describe node k8s-master | grep -A3 Taints
kubectl get pods -A -o wide
```

Expected:

- master Ready and tainted
- worker1 Ready with `node-role=siem`
- worker2 Ready with `node-role=soar`
- no SOC pods on master

## Storage

```bash
bash scripts/99_verify_storage_layout.sh
kubectl get pv,pvc -A
kubectl describe pv socaas-pv-wazuh-indexer | grep -A8 NodeAffinity
kubectl describe pv socaas-pv-cassandra | grep -A8 NodeAffinity
```

## Services

```bash
kubectl get svc -A | grep socaas
sudo ss -tlnp | grep haproxy
curl -k https://192.168.122.1:6443/version
curl -I http://192.168.122.1:30080
curl -I http://192.168.122.1:30900
```

## Pipeline

```bash
bash scripts/13_test_alert_pipeline.sh
kubectl logs -n socaas-soar deployment/socaas-pipeline-gateway --tail=100
```

## Evidence bundle commands

```bash
source env/socaas.env
mkdir -p "${SOCAAS_GENERATED_DIR}/evidence"
kubectl get nodes -o wide --show-labels > "${SOCAAS_GENERATED_DIR}/evidence/nodes.txt"
kubectl get pods -A -o wide > "${SOCAAS_GENERATED_DIR}/evidence/pods.txt"
kubectl get svc -A > "${SOCAAS_GENERATED_DIR}/evidence/services.txt"
kubectl get pv,pvc -A > "${SOCAAS_GENERATED_DIR}/evidence/storage.txt"
kubectl get networkpolicy -A > "${SOCAAS_GENERATED_DIR}/evidence/networkpolicies.txt"
helm list -A > "${SOCAAS_GENERATED_DIR}/evidence/helm.txt"
```
