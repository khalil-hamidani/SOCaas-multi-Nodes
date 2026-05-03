# 12 - Shuffle Deployment

Shuffle runs only on `k8s-worker2` in namespace `socaas-soar`.

Components:

- Shuffle frontend
- Shuffle backend
- Shuffle orborus/worker
- Redis
- OpenSearch datastore
- SOCaaS pipeline gateway

## Services

| Service | Type | Port |
|---|---|---|
| `socaas-shuffle-frontend` | NodePort | 30080 |
| `socaas-shuffle-backend` | ClusterIP | 5001 |
| `socaas-shuffle-opensearch` | ClusterIP | 9200 |
| `socaas-redis` | ClusterIP | 6379 |
| `socaas-pipeline-gateway` | ClusterIP | 8080 |

## First login

Open:

```text
http://192.168.122.1:30080
```

Create the first Shuffle account. The chart provides default credentials as environment variables where supported, but Shuffle normally asks for first-account setup in the UI.

## Native Shuffle webhook

For the thesis demo:

1. Create a workflow named `socaas-wazuh-alert-router`.
2. Add a webhook trigger.
3. Copy the generated webhook URL.
4. Set `SOCAAS_NATIVE_SHUFFLE_WEBHOOK_URL` in `env/socaas.env`.
5. Rerun `scripts/11_deploy_socaas.sh`.

The pipeline gateway will forward Wazuh alerts to that native Shuffle URL.
