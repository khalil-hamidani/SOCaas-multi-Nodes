# 15 - Alert Pipeline Test

Run:

```bash
bash scripts/13_test_alert_pipeline.sh
```

The script sends a sample Wazuh-style alert from inside the cluster to:

```text
http://socaas-pipeline-gateway.socaas-soar.svc.cluster.local:8080/hooks/wazuh
```

Expected results:

1. The test pod prints an accepted JSON response.
2. The pipeline gateway logs the alert rule ID.
3. If `SOCAAS_NATIVE_SHUFFLE_WEBHOOK_URL` is configured, the gateway also forwards to Shuffle.
4. If a valid TheHive API key is configured, the gateway creates an alert/case in TheHive.

Create a real endpoint event:

```bash
# On the separate Wazuh agent laptop
logger "SOCaaS test suspicious command $(date)"
touch /tmp/socaas-fim-test.txt
rm /tmp/socaas-fim-test.txt
```

Then check Wazuh and gateway logs:

```bash
kubectl logs -n socaas-siem statefulset/socaas-wazuh-manager -c alert-forwarder --tail=100
kubectl logs -n socaas-soar deployment/socaas-pipeline-gateway --tail=100
```
