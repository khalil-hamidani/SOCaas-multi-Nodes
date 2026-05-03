# 14 - Wazuh Agent Setup

Run these commands on the separate monitored laptop, not on the Parrot host and not inside the Kubernetes VMs.

## Ubuntu/Debian endpoint

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
printf 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main\n' | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update
sudo WAZUH_MANAGER="192.168.122.1" WAZUH_PROTOCOL="tcp" apt install -y wazuh-agent
sudo systemctl enable --now wazuh-agent
sudo systemctl status wazuh-agent --no-pager
```

If the endpoint is not on the libvirt network, use the Parrot host LAN/Wi-Fi IP instead of `192.168.122.1` and make sure firewall/NAT allows the laptop to reach HAProxy.

## Manual ossec.conf check

```bash
sudo grep -n "<address>" /var/ossec/etc/ossec.conf
sudo sed -n '/<client>/,/<\/client>/p' /var/ossec/etc/ossec.conf
```

Expected manager address:

```xml
<address>192.168.122.1</address>
```

## Verify from Wazuh Manager

```bash
kubectl exec -n socaas-siem statefulset/socaas-wazuh-manager -c wazuh-manager -- /var/ossec/bin/agent_control -l
```
