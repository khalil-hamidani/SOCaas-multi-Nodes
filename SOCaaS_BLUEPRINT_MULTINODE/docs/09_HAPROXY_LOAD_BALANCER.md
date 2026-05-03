# 09 - HAProxy Load Balancer

HAProxy runs on the Parrot host, not as a Kubernetes pod.

Install and configure:

```bash
bash scripts/09_install_haproxy_host.sh
```

## Exposed services

| HAProxy bind | Backend | Purpose |
|---|---|---|
| `*:6443` | `192.168.122.10:6443` | Kubernetes API |
| `*:1514` | `192.168.122.11:31514` | Wazuh agent events over TCP |
| `*:1515` | `192.168.122.11:31515` | Wazuh agent enrollment |
| `*:55000` | `192.168.122.11:31550` | Wazuh API |
| `*:30000` | `192.168.122.11:31514` | Wazuh manager compatibility port |
| `*:30002` | `192.168.122.11:30002` | Wazuh Dashboard |
| `*:30080` | `192.168.122.12:30080` | Shuffle UI |
| `*:30900` | `192.168.122.12:30900` | TheHive UI |
| `*:8404` | local | HAProxy stats |

## Verification

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo ss -tlnp | grep haproxy
curl -k https://192.168.122.1:6443/version
```

Stats page:

```text
http://192.168.122.1:8404/stats
user: admin
password: admin
```

Change the stats password before any demo on an untrusted network.
