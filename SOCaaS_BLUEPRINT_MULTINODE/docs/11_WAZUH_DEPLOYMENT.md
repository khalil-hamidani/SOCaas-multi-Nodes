# 11 - Wazuh Deployment

Wazuh runs only on `k8s-worker1` in namespace `socaas-siem`.

Components:

- Wazuh Indexer or compatible OpenSearch-based indexer
- Wazuh Manager
- Wazuh Dashboard
- alert forwarder sidecar that tails Wazuh alerts and posts to the pipeline gateway

## Services

| Service | Type | Port |
|---|---|---|
| `socaas-wazuh-indexer` | ClusterIP | 9200 |
| `socaas-wazuh-manager` | ClusterIP | 1514, 1515, 55000 |
| `socaas-wazuh-manager-nodeport` | NodePort | 31514, 31515, 31550 |
| `socaas-wazuh-dashboard` | NodePort | 30002 -> container 5601 |

## Verification

```bash
kubectl get pods -n socaas-siem -o wide
kubectl get svc -n socaas-siem
kubectl logs -n socaas-siem statefulset/socaas-wazuh-manager -c wazuh-manager --tail=100
kubectl logs -n socaas-siem statefulset/socaas-wazuh-manager -c alert-forwarder --tail=100
```

## Agent ports

For the separate endpoint laptop, use TCP transport where possible:

```text
manager address: 192.168.122.1
agent events:    tcp/1514
agent enroll:    tcp/1515
```

The compatibility HAProxy port `30000` forwards to the Wazuh manager event NodePort for users following the older guide.
