# 18 - Security Hardening

## Immediate changes after first deployment

1. Change Wazuh dashboard password.
2. Change Shuffle admin password.
3. Change TheHive secret and create real user/API keys.
4. Change MinIO root credentials.
5. Change HAProxy stats password.
6. Replace lab self-signed certificates with your own CA or ACME-issued certificates.

## Kubernetes security

- Keep the control-plane taint.
- Keep namespaces separated.
- Keep default-deny network policies.
- Do not mount Docker or Podman sockets into pods.
- Avoid privileged pods except temporary debugging.
- Use Secrets for credentials, not ConfigMaps.

## TLS notes

The Wazuh dashboard and Wazuh internal services often require TLS/certificates in production. The lab chart favors low-resource repeatability. For production:

- use Wazuh official certificate generation or cert-manager;
- enable OpenSearch/Wazuh Indexer security plugin;
- enforce HTTPS from HAProxy to backends;
- disable plain HTTP NodePorts;
- restrict HAProxy listener addresses.

## Host firewall

Only expose required ports:

```bash
sudo ufw allow 6443/tcp
sudo ufw allow 1514/tcp
sudo ufw allow 1515/tcp
sudo ufw allow 55000/tcp
sudo ufw allow 30002/tcp
sudo ufw allow 30080/tcp
sudo ufw allow 30900/tcp
sudo ufw allow 8404/tcp
```

Do not expose NodePort range broadly outside the lab.
