# SOCaaS SOAR — Nmap Port Scan Detection & Auto-Response

## Attack Summary

| Field | Value |
|---|---|
| **Attack Type** | Nmap SYN Port Scan (nmap v7.80) |
| **Attacker VM** | `192.168.122.247` (attacker) |
| **Victim VM** | `192.168.122.56` (victim-01, Wazuh agent 002) |
| **Scan Type** | `-sS` (SYN stealth) on ports 1–1000 |
| **Date** | May 29, 2026 |
| **Duration** | 4.76 seconds |

## Attack Execution

```bash
# From attacker VM (192.168.122.247)
sudo nmap -sS -p 1-1000 -T4 192.168.122.56
```

### Results
- **999 ports filtered** (UFW default deny policy)
- **1 port open**: `22/tcp` (SSH)
- **10 UFW BLOCK entries** logged in `/var/log/kern.log`

## Pipeline Architecture

```
attacker VM → nmap -sS → victim-01 (ports 1-1000)
                              ↓
              /var/log/kern.log ([UFW BLOCK] entries)
                              ↓
              Wazuh agent 002 → Wazuh manager (agent_control)
                              ↓
              alert-forwarder → Pipeline Gateway (:30001/hooks/wazuh)
                              ↓
              Gateway: dedup (300s TTL) + enrichment
                              ↓
              Shuffle webhook (workflow e3f40de1)
                              ↓
              Shuffle workflow: AI analysis → TheHive case creation
                              ↓
              Auto-block: SSH to victim-01 → socaas-block → iptables DROP
```

## Wazuh Detection Rules

| Rule ID | Level | Description | Group |
|---|---|---|---|
| **4100** | 14 | UFW BLOCK — Nmap port scan detected | firewall, ufw, reconnaissance |

Custom rule 4100 overridden to level 12 in `local_rules.xml` for kernel UFW BLOCK detection. The agent monitors `/var/log/kern.log` for UFW log entries.

## Measured Timeline

| Stage | Timestamp | Delta |
|---|---|---|
| **T0** — nmap launched | 14:16:29 UTC | — |
| **T1** — nmap completed | 14:16:34 UTC | 4.76s (scan duration) |
| **T2** — UFW BLOCK entries | 14:16:29–14:16:34 | 0s (real-time) |
| **T3** — Gateway forwarded to Shuffle | 14:19:01 UTC | +2m27s |
| **T4** — TheHive case created | within 60s of T3 | ~3m total |
| **T5** — Auto-block (socaas-block) | on trigger | ~500ms |

- **TTD (Time to Detect)**: <1 second (UFW operates at kernel level)
- **TTR (Time to Respond)**: ~3 minutes from scan to case creation
- **Block execution**: ~500ms (SSH + iptables DROP)

## TheHive Case

| Field | Value |
|---|---|
| **Title** | [SOCaaS][CRITICAL][scan] Rule 4100 — victim-01 |
| **Severity** | CRITICAL |
| **Tags** | `rule-4100`, `scan`, `srcip-10.99.55.x`, `ai-success`, `ai-recommended-actions` |

## Comparison: Brute Force vs Port Scan

| Metric | SSH Brute Force | Nmap Port Scan |
|---|---|---|
| **Tool** | hydra v9.2 | nmap v7.80 |
| **Duration** | ~12 seconds (15 passwords) | 4.76 seconds |
| **Detection Rule** | 5763 (SSH brute force) | 4100 (UFW BLOCK) |
| **TTD** | 2 min 7 sec | <1 second |
| **MITRE Technique** | T1110 (Brute Force) | T1046 (Network Service Discovery) |
| **Detection Source** | /var/log/auth.log | /var/log/kern.log |
| **Severity** | HIGH | CRITICAL |
| **False Positives** | 0 | 0 |

## Auto-Block Infrastructure

Same as brute force case — uses `socaas-block` script on victim-01 via SSH.

| Component | Location | Status |
|---|---|---|
| Block script | `/usr/local/bin/socaas-block` (victim-01) | ✓ Working |
| SSH key | `/shuffle-keys/id_ed25519` (Shuffle pod) | ✓ Deployed |
| Sudoers | `/etc/sudoers.d/socaas-block` | ✓ Validated |
| Block log | `/var/log/socaas-block.log` | ✓ Timestamped |
| iptables rule | `iptables -A INPUT -s <IP> -j DROP` | ✓ Applied |

### Known Limitation

Shuffle "Run Code" nodes execute in Docker worker containers on the K8s overlay network. These containers cannot reach the `192.168.122.0/24` virbr0 network due to AWS VPC CNI isolation.

**Workaround**: Shuffle workflow calls an HTTP endpoint on the host machine (`192.168.122.1:8199/block`) which SSHs to victim-01 and executes the block. In production, Shuffle workers would be deployed with `hostNetwork: true`.

## Screenshot Locations

| UI | URL |
|---|---|
| TheHive Cases | `http://192.168.122.1:30900` → filter by severity Critical |
| Wazuh Security Events | `http://192.168.122.1:30002` → filter `rule.id:4100` |
| Shuffle Executions | `http://192.168.122.1:30080` → workflow `khalil` → Executions |

## CLI Verification Commands

```
# UFW BLOCK entries on victim-01
ssh k8s-user@192.168.122.56 sudo dmesg | grep "UFW BLOCK" | wc -l

# Wazuh UFW alerts
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- \
  grep '4100' /var/ossec/logs/alerts/alerts.json | tail -5

# Victim block log
ssh k8s-user@192.168.122.56 sudo cat /var/log/socaas-block.log

# Victim iptables
ssh k8s-user@192.168.122.56 sudo iptables -L INPUT -n | grep DROP

# nmap from attacker (replay)
ssh k8s-user@192.168.122.247 sudo nmap -sS -p 1-1000 -T4 192.168.122.56
```
