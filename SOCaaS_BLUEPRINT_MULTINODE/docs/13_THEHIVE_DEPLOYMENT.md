# 13 - TheHive Deployment

TheHive runs only on `k8s-worker2` in namespace `socaas-thehive`.

Components:

- TheHive application
- Cassandra database
- Elasticsearch-compatible index backend
- MinIO object storage

## Services

| Service | Type | Port |
|---|---|---|
| `socaas-thehive` | NodePort | 30900 |
| `socaas-cassandra` | ClusterIP | 9042 |
| `socaas-thehive-elasticsearch` | ClusterIP | 9200 |
| `socaas-minio` | ClusterIP | 9000 |

## Verification

```bash
kubectl get pods -n socaas-thehive -o wide
kubectl logs -n socaas-thehive statefulset/socaas-cassandra --tail=100
kubectl logs -n socaas-thehive deployment/socaas-thehive --tail=100
curl -f http://192.168.122.1:30900 || true
```

## TheHive API key

For full automated case creation, create an organization and API key in TheHive, then update the `thehive.apiKey` value or Kubernetes Secret. Until that key is set, the pipeline gateway still logs received alerts and can forward to a native Shuffle webhook.
