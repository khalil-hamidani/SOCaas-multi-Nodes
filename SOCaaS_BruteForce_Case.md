# SOCaaS SOAR — SSH Brute Force Detection & Auto-Response

## Attack Summary

| Field | Value |
|---|---|
| **Attack Type** | SSH Brute Force (hydra v9.2) |
| **Attacker VM** | `192.168.122.247` (attacker) |
| **Victim VM** | `192.168.122.56` (victim-01, Wazuh agent 002) |
| **Target User** | `root` |
| **Password List** | 15 entries (admin, password, 123456, root, toor...) |
| **Total Attempts** | 108+ failed SSH logins |
| **Date** | May 29, 2026 |
| **Duration** | ~6 hours of continuous testing |

## Pipeline Architecture

```
attacker VM → hydra → victim-01:22
                          ↓
              /var/log/auth.log (Failed password entries)
                          ↓
              Wazuh agent 002 → Wazuh manager (agent_control)
                          ↓
              alert-forwarder → Pipeline Gateway (:30001/hooks/wazuh)
                          ↓
              Gateway: dedup (300s TTL) + VirusTotal enrichment
                          ↓
              Shuffle webhook (workflow e3f40de1)
                          ↓
              Shuffle workflow: AI analysis → TheHive case creation
                          ↓
              Auto-block: SSH to victim-01 → socaas-block → iptables DROP
```

## Wazuh Detection Rules Triggered

| Rule ID | Level | Description | MITRE |
|---|---|---|---|
| **5763** | 10 | sshd: brute force trying to get access to the system | T1110 Brute Force |
| **5712** | 10 | sshd: brute force trying to get access (non-existent user) | T1110 |
| **5551** | 10 | PAM: Multiple failed logins in a small period of time | T1110 |
| **40112** | 12 | Multiple authentication failures followed by a success | T1078/T1110 |
| **2502** | 10 | syslog: User missed the password more than one time | T1110 |
| **5760** | 5 | sshd: authentication failed | T1110.001 Password Guessing |
| **5710** | 5 | sshd: Attempt to login using a non-existent user | T1110.001 |

## Measured Timeline

| Stage | Timestamp | Delta |
|---|---|---|
| **T0** — Hydra launched | 12:10:22 UTC | — |
| **T1** — First auth.log entry | 12:10:22 UTC | 0s |
| **T2** — Wazuh Rule 5763 detected | 12:12:29 UTC | **TTD: 2m 07s** |
| **T3** — Gateway forwarded to Shuffle | 12:12:29 UTC | <1s |
| **T4** — TheHive case #534 created | 12:13:01 UTC | +32s |
| **T5** — Auto-block (socaas-block) | on trigger | ~500ms |

- **TTD (Time to Detect)**: 2 minutes 7 seconds
- **TTR (Time to Respond)**: ~3 minutes from attack to case creation
- **Block execution**: ~500ms (SSH + iptables DROP)

## TheHive Case Sample (#554)

| Field | Value |
|---|---|
| **Case ID** | #554 |
| **Title** | [SOCaaS][HIGH][auth] Rule 5763 — victim-01 |
| **Created** | 2026-05-29 12:33:01 UTC |
| **Severity** | HIGH |
| **Tags** | `rule-5763`, `ai-success`, `user-root`, `user-context`, `socaas`, `ai-recommended-actions`, `srcip-192.168.122.247`, `shuffle` |
| **AI Analysis** | ✓ Completed with recommendations |

## Total TheHive Cases Created

**132 cases** across 6 hours of testing (May 29, 2026). All tagged with:
- `ai-success` — AI analysis completed
- `ai-recommended-actions` — analyst recommendations generated
- Zero false positives across all detections

## Auto-Block Infrastructure

| Component | Location | Status |
|---|---|---|
| Block script | `/usr/local/bin/socaas-block` (victim-01) | ✓ Working |
| SSH key | `/shuffle-keys/id_ed25519` (Shuffle pod) | ✓ Deployed |
| Sudoers | `/etc/sudoers.d/socaas-block` | ✓ Validated |
| Block log | `/var/log/socaas-block.log` | ✓ Timestamped |
| iptables rule | `iptables -A INPUT -s <IP> -j DROP` | ✓ Applied |

### Block Script Validation

- ✓ Rejects `127.0.0.1`, `0.0.0.0`, `255.255.255.255`
- ✓ Validates IPv4 format and octet ranges
- ✓ Detects duplicate iptables rules (exit 0 if already blocked)
- ✓ Logs with UTC millisecond precision
- ✓ Requires root execution (Shuffle calls via `sudo`)

### Known Limitation

Shuffle "Run Code" nodes execute in Docker worker containers on the K8s overlay network. These containers cannot reach the `192.168.122.0/24` virbr0 network due to AWS VPC CNI isolation. 

**Workaround**: Shuffle workflow calls an HTTP endpoint on the host machine (`192.168.122.1:8199/block`) which SSHs to victim-01 and executes the block. In production, Shuffle workers would be deployed with `hostNetwork: true`.

## Screenshot Locations

| UI | URL |
|---|---|
| TheHive Cases | `http://192.168.122.1:30900` → Cases #506, #534, #554, #570, #589, #594 |
| Wazuh Security Events | `http://192.168.122.1:30002` → filter `rule.id:(5763 OR 5712)` |
| Shuffle Executions | `http://192.168.122.1:30080` → workflow `khalil` → Executions |

## CLI Verification Commands

```
# Wazuh brute force alerts
kubectl exec -n socaas-siem socaas-wazuh-manager-0 -c wazuh-manager -- \
  grep '5763' /var/ossec/logs/alerts/alerts.json | grep '192.168.122.247' | tail -1

# Victim block log
ssh k8s-user@192.168.122.56 sudo cat /var/log/socaas-block.log

# Victim iptables
ssh k8s-user@192.168.122.56 sudo iptables -L INPUT -n | grep DROP

# Auth.log sample
ssh k8s-user@192.168.122.56 sudo grep "Failed password.*192.168.122.247" /var/log/auth.log | wc -l
```
