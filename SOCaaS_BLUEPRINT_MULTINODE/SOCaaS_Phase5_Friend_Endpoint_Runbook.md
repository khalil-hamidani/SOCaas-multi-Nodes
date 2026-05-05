# SOCaaS Phase 5 Runbook — Link Your Friend’s Parrot/VM Endpoint to Your SOC

This runbook explains exactly what to do on **your SOC host**, **your friend’s Parrot host**, and **your friend’s monitored Linux VM** so the external endpoint sends telemetry into your SOCaaS stack.

Your current SOC status before starting this phase:

```text
Step 0  Host preparation        DONE
Step 1  KVM/VM provisioning     DONE
Step 2  Kubernetes + Calico     DONE
Step 3  Labels/storage/HAProxy  DONE
Step 4  SOCaaS stack            DONE
```

Phase 5 goal:

```text
Friend Linux VM -> Wazuh Agent -> Your SOC host HAProxy -> Wazuh Manager -> Pipeline Gateway -> Shuffle/TheHive
```

---

## 0. Architecture for this phase

### Your side

```text
Your Parrot host
  - Runs KVM/libvirt
  - Runs HAProxy on host network
  - Exposes Wazuh/Shuffle/TheHive ports
  - Has Kubernetes VMs behind libvirt NAT

Kubernetes cluster
  - k8s-master   192.168.122.10
  - k8s-worker1  192.168.122.11  Wazuh/SIEM
  - k8s-worker2  192.168.122.12  Shuffle/TheHive/SOAR
```

### Friend side

Recommended:

```text
Friend Parrot host
  - Runs virsh/libvirt
  - Runs a small monitored Linux VM

Friend Linux VM
  - Has Wazuh Agent installed
  - Connects outbound to your SOC host LAN/VPN IP
```

Important: your friend’s endpoint should connect to your **SOC host LAN/VPN IP**, not to `192.168.122.x`. The `192.168.122.x` network is your internal libvirt network and usually is not reachable from your friend’s machine.

---

## 1. Fill in your variables

Before running commands, decide these values.

```bash
# On YOUR SOC host
export SOC_HOST_LAN_IP="REPLACE_WITH_YOUR_PARROT_LAN_OR_VPN_IP"

# On your FRIEND'S endpoint VM
export SOC_MANAGER_IP="REPLACE_WITH_YOUR_PARROT_LAN_OR_VPN_IP"
export WAZUH_AGENT_NAME="friend-parrot-vm-01"
```

Examples:

```text
Same Wi-Fi/LAN example:
SOC_HOST_LAN_IP=192.168.1.50

Tailscale/VPN example:
SOC_HOST_LAN_IP=100.90.12.34
```

Do **not** use these as the friend endpoint manager address unless the friend VM can really reach them:

```text
192.168.122.1
192.168.122.10
192.168.122.11
192.168.122.12
```

---

## 2. Network options

### Option A — Same LAN or same Wi-Fi, recommended

Use this if both laptops are connected to the same router/Wi-Fi.

Your friend’s VM uses NAT on his Parrot host. NAT is fine because the Wazuh Agent connects outbound to your SOC.

```text
Friend VM -> Friend Parrot NAT -> LAN -> Your Parrot host -> HAProxy -> Wazuh Manager
```

### Option B — VPN, recommended if remote

Use Tailscale or WireGuard if your friend is not on the same LAN.

```text
Friend VM/host -> VPN IP of your Parrot host -> HAProxy -> Wazuh Manager
```

Do **not** expose Wazuh ports directly to the public internet for this lab.

### Option C — Public internet, avoid for now

Avoid exposing these ports directly:

```text
1514 TCP/UDP
1515 TCP
55000 TCP
30002 TCP
30080 TCP
30900 TCP
```

Use a VPN instead.

---

# PART A — Commands on YOUR SOC host

Run this section on your Parrot SOC host.

---

## A1. Start/verify your SOC stack

```bash
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE

virsh list --all
ssh k8s-user@192.168.122.10 'kubectl get nodes -o wide'
ssh k8s-user@192.168.122.10 'kubectl get pods -A -o wide'
ssh k8s-user@192.168.122.10 'helm list -A'
```

Expected:

```text
k8s-master    Ready
k8s-worker1   Ready
k8s-worker2   Ready
socaas        deployed
all SOCaaS pods Running
```

Run the blueprint verifier:

```bash
bash scripts/12_verify_cluster.sh
```

---

## A2. Find your SOC host LAN IP

Run:

```bash
hostname -I
ip -4 addr | grep -v '127.0.0.1'
```

Pick the IP that your friend can reach. Example:

```bash
export SOC_HOST_LAN_IP="192.168.1.50"
```

If using VPN/Tailscale, use your VPN IP instead.

---

## A3. Confirm HAProxy is listening

```bash
sudo systemctl is-active haproxy
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo ss -ltnup | grep -E ':1514|:1515|:55000|:30002|:30080|:30900|:8404|:6443'
```

Expected listening ports:

```text
6443   Kubernetes API through HAProxy
1514   Wazuh agent event input
1515   Wazuh agent enrollment
55000  Wazuh API
30002  Wazuh Dashboard
30080  Shuffle UI
30900  TheHive UI
8404   HAProxy stats
```

---

## A4. Allow firewall access from your friend

If you use UFW:

```bash
sudo ufw allow from <FRIEND_LAN_OR_VPN_IP> to any port 1514 proto tcp
sudo ufw allow from <FRIEND_LAN_OR_VPN_IP> to any port 1514 proto udp
sudo ufw allow from <FRIEND_LAN_OR_VPN_IP> to any port 1515 proto tcp
sudo ufw allow from <FRIEND_LAN_OR_VPN_IP> to any port 55000 proto tcp
sudo ufw allow from <FRIEND_LAN_OR_VPN_IP> to any port 30002 proto tcp
sudo ufw allow from <FRIEND_LAN_OR_VPN_IP> to any port 30080 proto tcp
sudo ufw allow from <FRIEND_LAN_OR_VPN_IP> to any port 30900 proto tcp
sudo ufw status numbered
```

If UFW is not enabled, just continue and test connectivity from your friend’s VM.

---

## A5. Quick SOC endpoint checks from your host

```bash
curl -I http://192.168.122.1:30002 || true
curl -I http://192.168.122.1:30080 || true
curl -I http://192.168.122.1:30900 || true
```

Expected:

```text
Wazuh Dashboard: not 503
Shuffle: HTTP response
TheHive: HTTP response, 404 is acceptable because app path may differ
```

---

# PART B — Commands on your FRIEND'S Parrot host

Run this section on your friend’s physical Parrot laptop.

Your friend can either install Wazuh Agent directly on his Parrot host or, better, create a small VM and install the agent inside the VM.

Recommended for the cleanest project/demo: **install Wazuh Agent inside a small Linux VM**.

---

## B1. Install/check KVM tools on friend Parrot host

```bash
sudo apt update
sudo apt install -y qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager virtinst qemu-utils bridge-utils
sudo systemctl enable --now libvirtd 2>/dev/null || sudo systemctl enable --now libvirt-daemon
virsh list --all
virsh net-list --all
```

If `virsh` does not work without sudo, use:

```bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.zshrc
source ~/.zshrc
```

---

## B2. Create a small endpoint VM

Recommended VM resources:

```text
Name: socaas-endpoint-01
OS: Ubuntu/Debian/Parrot minimal
vCPU: 2
RAM: 2-4 GB
Disk: 20-30 GB
Network: default NAT is fine
```

### Easy option: virt-manager GUI

```bash
virt-manager
```

Create a VM normally and attach it to the default NAT network.

### CLI example

Adjust the ISO path:

```bash
virt-install \
  --name socaas-endpoint-01 \
  --memory 2048 \
  --vcpus 2 \
  --disk size=25,path=$HOME/socaas-endpoint-01.qcow2,format=qcow2 \
  --cdrom /path/to/linux.iso \
  --network network=default \
  --graphics spice \
  --os-variant ubuntu22.04
```

After installation, boot the VM and log in.

---

# PART C — Commands inside your FRIEND'S endpoint VM

Run this section inside the friend’s small Linux VM.

---

## C1. Test network to your SOC host

Set your SOC host IP:

```bash
export SOC_MANAGER_IP="REPLACE_WITH_YOUR_SOC_HOST_LAN_OR_VPN_IP"
export WAZUH_AGENT_NAME="friend-parrot-vm-01"
```

Test connectivity:

```bash
ping -c 3 "$SOC_MANAGER_IP"
```

Install netcat if needed:

```bash
sudo apt update
sudo apt install -y netcat-openbsd curl gpg
```

Test Wazuh ports:

```bash
nc -vz "$SOC_MANAGER_IP" 1515
nc -vz "$SOC_MANAGER_IP" 1514
nc -vz "$SOC_MANAGER_IP" 55000
```

Expected:

```text
1515 open  enrollment
1514 open  event transport
55000 open Wazuh API path, optional but useful
```

If these fail, fix LAN/VPN/firewall before installing the agent.

---

## C2. Install the Wazuh Agent

For Debian/Ubuntu/Parrot-based endpoints:

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
printf 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main\n' | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update

sudo WAZUH_MANAGER="$SOC_MANAGER_IP" \
     WAZUH_REGISTRATION_SERVER="$SOC_MANAGER_IP" \
     WAZUH_AGENT_NAME="$WAZUH_AGENT_NAME" \
     WAZUH_PROTOCOL="tcp" \
     apt install -y wazuh-agent

sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
sudo systemctl status wazuh-agent --no-pager
```

If the package was already installed before, manually configure it:

```bash
sudo cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.$(date +%F_%H-%M)
sudo sed -i "s#<address>.*</address>#<address>${SOC_MANAGER_IP}</address>#" /var/ossec/etc/ossec.conf
sudo sed -i "s#<protocol>.*</protocol>#<protocol>tcp</protocol>#" /var/ossec/etc/ossec.conf
sudo /var/ossec/bin/agent-auth -m "$SOC_MANAGER_IP" -p 1515 -A "$WAZUH_AGENT_NAME" || true
sudo systemctl restart wazuh-agent
```

Verify config:

```bash
sudo sed -n '/<client>/,/<\/client>/p' /var/ossec/etc/ossec.conf
sudo systemctl status wazuh-agent --no-pager
sudo tail -n 80 /var/ossec/logs/ossec.log
```

Expected in `ossec.conf`:

```xml
<client>
  <server>
    <address>YOUR_SOC_HOST_IP</address>
    <protocol>tcp</protocol>
  </server>
</client>
```

---

# PART D — Verify the agent from YOUR SOC host

Run this section on your SOC host or via SSH to `k8s-master`.

---

## D1. Check Wazuh agent list

```bash
ssh k8s-user@192.168.122.10 '
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l
'
```

Expected:

```text
friend-parrot-vm-01
Active
```

If the agent is not visible, check manager logs:

```bash
ssh k8s-user@192.168.122.10 '
kubectl logs -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager --tail=120 | grep -Ei "agent|auth|register|connect|1515|1514" || true
'
```

Check HAProxy sees connections:

```bash
sudo ss -tanp | grep -E ':1514|:1515|:55000' || true
```

---

## D2. Open Wazuh Dashboard

On your browser:

```text
http://YOUR_SOC_HOST_LAN_OR_VPN_IP:30002
```

In your lab, your local bridge test is:

```bash
curl -I http://192.168.122.1:30002
```

For your friend, use your LAN/VPN IP.

Inside Wazuh Dashboard, check:

```text
Agents -> friend-parrot-vm-01 -> Active
```

---

# PART E — Generate test events from friend's VM

Run these inside your friend’s endpoint VM.

---

## E1. Basic log event

```bash
logger "SOCaaS test suspicious command from ${HOSTNAME} at $(date)"
```

Then on your SOC host:

```bash
ssh k8s-user@192.168.122.10 '
kubectl logs -n socaas-siem socaas-wazuh-manager-0 -c alert-forwarder --tail=100
kubectl logs -n socaas-soar deployment/socaas-pipeline-gateway --tail=100
'
```

---

## E2. Reliable FIM test path

Inside the friend endpoint VM, add a monitored directory to the Wazuh Agent config.

Backup config:

```bash
sudo cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.fim.$(date +%F_%H-%M)
```

Add a FIM monitored directory inside the existing `<syscheck>` block:

```bash
sudo sed -i '/<syscheck>/a\    <directories realtime="yes">/tmp/socaas-fim</directories>' /var/ossec/etc/ossec.conf
sudo mkdir -p /tmp/socaas-fim
sudo systemctl restart wazuh-agent
```

Trigger file events:

```bash
echo "SOCaaS FIM create test $(date)" | sudo tee /tmp/socaas-fim/test-create.txt
sudo sh -c 'echo modified >> /tmp/socaas-fim/test-create.txt'
sudo rm -f /tmp/socaas-fim/test-create.txt
```

Check Wazuh Dashboard for file integrity alerts related to:

```text
/tmp/socaas-fim
```

---

## E3. Optional EICAR malware simulation

Only do this in a lab VM, not on a production machine.

```bash
mkdir -p /tmp/socaas-eicar
cat > /tmp/socaas-eicar/eicar.com.txt <<'__EICAR__'
X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
__EICAR__
```

This is not real malware, but security tools often detect it as a test signature.

---

# PART F — Test the deterministic alert pipeline

Run this on YOUR SOC host:

```bash
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE
bash scripts/13_test_alert_pipeline.sh
```

Expected:

```text
The test pod posts a sample Wazuh-style alert to the pipeline gateway.
The pipeline gateway logs the alert rule ID.
```

Check logs manually:

```bash
ssh k8s-user@192.168.122.10 '
kubectl logs -n socaas-soar deployment/socaas-pipeline-gateway --tail=100
kubectl logs -n socaas-siem socaas-wazuh-manager-0 -c alert-forwarder --tail=100
'
```

---

# PART G — Link Shuffle, TheHive, and VirusTotal later

Phase 5 first proves that the external Wazuh Agent works. After that, you can make the SOAR workflow richer.

---

## G1. Shuffle native webhook

1. Open Shuffle:

```text
http://YOUR_SOC_HOST_LAN_OR_VPN_IP:30080
```

2. Create or import a workflow.
3. Add a webhook trigger.
4. Copy the webhook URL.
5. Put it in your SOC host env file:

```bash
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE
nano env/socaas.env
```

Set:

```bash
export SOCAAS_NATIVE_SHUFFLE_WEBHOOK_URL="PASTE_SHUFFLE_WEBHOOK_URL_HERE"
```

Redeploy only after saving:

```bash
bash scripts/11_deploy_socaas.sh
bash scripts/13_test_alert_pipeline.sh
```

---

## G2. TheHive API key

1. Open TheHive:

```text
http://YOUR_SOC_HOST_LAN_OR_VPN_IP:30900
```

2. Create/login to admin user.
3. Generate API key for automation.
4. Use it in Shuffle or future integration secrets.

---

## G3. VirusTotal

VirusTotal is not deployed inside Kubernetes. It is an external enrichment API used by Shuffle.

Typical workflow:

```text
Wazuh alert -> Pipeline Gateway -> Shuffle webhook -> VirusTotal lookup -> TheHive case
```

Use the VirusTotal API key inside Shuffle credentials or a Kubernetes secret, depending on how you build the workflow.

Do not hardcode API keys in public files.

---

# PART H — Success checklist

You are done with this phase when all are true:

```text
[ ] Friend endpoint VM can ping your SOC host LAN/VPN IP
[ ] Friend endpoint VM can connect to SOC ports 1514 and 1515
[ ] wazuh-agent service is active on friend VM
[ ] Wazuh Manager lists friend-parrot-vm-01 as Active
[ ] Wazuh Dashboard shows the agent as Active
[ ] logger/FIM test creates Wazuh events
[ ] scripts/13_test_alert_pipeline.sh succeeds
[ ] Pipeline gateway logs the sample alert
[ ] No SOCaaS pods are CrashLooping or Pending
```

Final validation commands:

```bash
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE
bash scripts/12_verify_cluster.sh
bash scripts/13_test_alert_pipeline.sh

ssh k8s-user@192.168.122.10 '
kubectl get pods -A -o wide
kubectl get pods -A | grep -E "CrashLoop|ImagePull|Init|Pending|ContainerCreating" || echo "No bad states"
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l
'
```

---

# PART I — Troubleshooting

## Friend VM cannot reach your SOC host

On friend VM:

```bash
ping -c 3 "$SOC_MANAGER_IP"
nc -vz "$SOC_MANAGER_IP" 1515
nc -vz "$SOC_MANAGER_IP" 1514
```

On your SOC host:

```bash
hostname -I
sudo ss -ltnup | grep -E ':1514|:1515|:55000'
sudo systemctl status haproxy --no-pager
```

Fix firewall or use VPN.

---

## Agent installed but not visible in Wazuh

On friend VM:

```bash
sudo systemctl status wazuh-agent --no-pager
sudo tail -n 120 /var/ossec/logs/ossec.log
sudo /var/ossec/bin/agent-auth -m "$SOC_MANAGER_IP" -p 1515 -A "$WAZUH_AGENT_NAME" || true
sudo systemctl restart wazuh-agent
```

On SOC:

```bash
ssh k8s-user@192.168.122.10 '
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- /var/ossec/bin/agent_control -l
kubectl logs -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager --tail=120
'
```

---

## Dashboard works but no alerts appear

Check alert files and forwarder:

```bash
ssh k8s-user@192.168.122.10 '
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- ls -lh /var/ossec/logs/alerts || true
kubectl logs -n socaas-siem socaas-wazuh-manager-0 -c alert-forwarder --tail=120
kubectl logs -n socaas-soar deployment/socaas-pipeline-gateway --tail=120
'
```

---

## Pipeline script fails

Run:

```bash
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE
bash scripts/13_test_alert_pipeline.sh
```

Then inspect:

```bash
ssh k8s-user@192.168.122.10 '
kubectl get pods -n socaas-soar
kubectl logs -n socaas-soar deployment/socaas-pipeline-gateway --tail=200
'
```

---

# PART J — Clean shutdown after working

On your SOC host:

```bash
cd /srv/socaas/SOCaaS_BLUEPRINT_MULTINODE
bash scripts/12_verify_cluster.sh | tee /srv/socaas/logs/pre_shutdown_phase5_$(date +%F_%H-%M).log

for vm in k8s-worker2 k8s-worker1 k8s-master; do
  virsh shutdown "$vm" || true
done

sleep 30
virsh list --all
sudo poweroff
```

Start order when you return:

```bash
virsh start k8s-master
sleep 30
virsh start k8s-worker1
virsh start k8s-worker2
ssh k8s-user@192.168.122.10 'kubectl get nodes && kubectl get pods -A'
```

---

# Recommended final demo flow

Use this for your PFE/thesis demo:

```text
1. Show Kubernetes/SOCaaS healthy.
2. Show friend endpoint VM running Wazuh Agent.
3. Show the endpoint listed as Active in Wazuh Dashboard.
4. Generate a file integrity event on the friend VM.
5. Show Wazuh alert.
6. Run deterministic pipeline test.
7. Show pipeline gateway logs.
8. Optional: show Shuffle workflow trigger.
9. Optional: show TheHive case creation.
10. Optional: enrich file/IP/hash with VirusTotal.
```

