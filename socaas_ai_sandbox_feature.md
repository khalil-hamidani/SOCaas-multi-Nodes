# SOCaaS AI Sandbox Feature Design

## 1. Goal

The **AI Sandbox** feature adds automated malware analysis to the SOCaaS workflow.

When SOCaaS detects a malware-related alert from Wazuh, Shuffle will trigger a local sandbox orchestrator. The orchestrator creates a fresh temporary VM, transfers the suspicious sample into it, runs static and dynamic analysis, generates an AI-assisted malware report, attaches that report to the related TheHive case, and then destroys the temporary VM.

The main goal is to make every malware case richer by automatically answering:

- What is the suspicious file?
- What does VirusTotal say about it?
- What process created or executed it?
- What files, registry keys, processes, DNS queries, or network connections does it create?
- Is it only a test file like EICAR, or does it show malicious behavior?
- What should the analyst do next?

---

## 2. High-Level Architecture

```text
Wazuh Malware Alert
        |
        v
Shuffle Workflow
        |
        v
Normalize_SOC_Alert
        |
        v
Build_VirusTotal_Target
        |
        v
Virustotal_v3
        |
        v
Generate_AI_Recommended_Actions
        |
        v
Build_Context_TheHive_Email_Body
        |
        v
Request_AI_Sandbox_Analysis
        |
        v
Local AI Sandbox Orchestrator
        |
        +--> Create temporary sandbox VM
        +--> Transfer malware sample
        +--> Run static analysis
        +--> Run dynamic analysis
        +--> Collect artifacts
        +--> Generate AI report
        +--> Destroy sandbox VM
        |
        v
Attach_Sandbox_Report_To_TheHive
        |
        v
Send Telegram / Email / Final Response
```

---

## 3. Core Design Principle

The sandbox should be **ephemeral**.

Do not reuse one permanent sandbox VM. Instead, use this model:

```text
Golden Sandbox Template
        |
        v
Temporary linked clone per case
        |
        v
Run analysis
        |
        v
Collect report
        |
        v
Destroy VM and delete disk
```

This gives every malware sample a clean analysis environment.

---

## 4. Components

### 4.1 Shuffle

Shuffle remains the automation engine.

Its role is to:

1. Receive Wazuh alerts.
2. Normalize the alert.
3. Enrich observables using VirusTotal.
4. Use AI for recommended analyst actions.
5. Trigger sandbox analysis only for malware alerts.
6. Attach the sandbox report to TheHive.
7. Notify the analyst using Telegram and email.

### 4.2 Wazuh

Wazuh detects the malware activity from endpoints.

Important fields needed from Wazuh:

```json
{
  "agent": {
    "id": "002",
    "name": "win10-victim",
    "ip": "192.168.122.98"
  },
  "rule": {
    "id": "554",
    "level": 12,
    "description": "EICAR test file detected - known malware hash"
  },
  "data": {
    "file_name": "update_helper.exe",
    "file_path": "C:\\Users\\win10-victim\\AppData\\Roaming\\MicrosoftEdge\\update_helper.exe",
    "file_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
    "process_name": "powershell.exe",
    "username": "win10-victim\\khalil"
  }
}
```

### 4.3 TheHive

TheHive stores the final incident case.

The sandbox report should be attached to the related case as an observable or attachment.

Recommended TheHive case additions:

- Tag: `sandbox-analysis`
- Tag: `sandbox-completed`
- Tag: `malware-analysis`
- Tag: `ai-sandbox`
- Attachment: `sandbox_report_<case_id>.md`
- Optional attachment: `network.pcap`
- Optional attachment: `process_tree.json`
- Optional attachment: `filesystem_changes.json`

### 4.4 Local AI Sandbox Orchestrator

The orchestrator is a local service running on the SOCaaS host.

Example endpoint:

```text
http://192.168.122.1:5055/analyze
```

Its role is to safely execute controlled sandbox operations:

```text
create_sandbox_vm(case_id)
copy_sample_to_sandbox(sample)
run_static_analysis()
run_dynamic_analysis(timeout=5m)
collect_artifacts()
generate_ai_report()
attach_report_to_thehive(case_id)
destroy_sandbox_vm(case_id)
```

The AI model should not directly run arbitrary shell commands. The AI should summarize results and generate the final report, while the orchestrator controls the execution.

---

## 5. Sandbox VM Design

### 5.1 Golden Image

Create one clean Windows analysis VM:

```text
win10-sandbox-golden.qcow2
```

Install tools such as:

- Sysmon
- Procmon
- Process Explorer
- Autoruns
- Wireshark or packet collector
- FakeNet-NG or fake internet tools
- Python
- PowerShell logging
- YARA
- Detect It Easy
- PEStudio
- 7zip
- Sandbox runner script

After configuration, shut it down and never analyze malware directly in this VM.

### 5.2 Temporary Clone

For each case, create a linked clone:

```bash
qemu-img create -f qcow2 \
  -F qcow2 \
  -b /var/lib/libvirt/images/win10-sandbox-golden.qcow2 \
  /var/lib/libvirt/images/sandbox-SOC-CASEID.qcow2
```

Then boot it with libvirt:

```bash
virt-install \
  --name sandbox-SOC-CASEID \
  --memory 4096 \
  --vcpus 2 \
  --disk /var/lib/libvirt/images/sandbox-SOC-CASEID.qcow2 \
  --import \
  --network network=sandbox-net,model=virtio \
  --graphics none \
  --noautoconsole
```

### 5.3 Cleanup

Always destroy the VM after analysis:

```bash
virsh destroy sandbox-SOC-CASEID || true
virsh undefine sandbox-SOC-CASEID --nvram || true
rm -f /var/lib/libvirt/images/sandbox-SOC-CASEID.qcow2
rm -rf /opt/socaas-sandbox/runs/SOC-CASEID
```

The cleanup must run even if analysis fails.

---

## 6. Network Isolation

The sandbox VM must not be connected to the normal SOC lab network.

Recommended network:

```text
sandbox-net
```

Design:

```text
Sandbox VM
    |
    v
sandbox-net only
    |
    v
Fake Internet / Collector
    |
    v
No access to SOC systems
No access to Wazuh manager
No access to TheHive
No access to Shuffle
No access to personal network
```

Recommended libvirt network mode:

```text
isolated
```

Avoid giving real internet access at first. Use fake DNS and fake HTTP services instead.

---

## 7. Malware Sample Transfer

The alert may include a file path and hash, but not the actual file. You need a safe way to collect the sample.

### Option A: Endpoint Collector Service

A small protected agent runs on the Windows victim. The orchestrator asks it to upload the suspicious file.

Flow:

```text
Shuffle -> Orchestrator -> Endpoint Collector -> Sample Upload -> Sandbox
```

### Option B: Wazuh Active Response

Wazuh active response copies the suspicious file to a quarantine folder or uploads it to the orchestrator.

Flow:

```text
Wazuh alert -> Active Response -> Copy sample -> Orchestrator pulls sample
```

### Option C: Internal Sample Store

For testing, use a known internal sample repository.

Flow:

```text
Alert hash -> Sample store lookup -> Download sample -> Sandbox
```

Recommended for the first version: use an internal safe test sample store and EICAR.

---

## 8. Sandbox Analysis Workflow

For each malware case:

```text
1. Receive request from Shuffle.
2. Validate alert_type == malware.
3. Validate case_id exists.
4. Validate file_hash or file_path exists.
5. Create run directory.
6. Create linked clone VM.
7. Boot VM on sandbox-net.
8. Wait until sandbox agent is ready.
9. Transfer malware sample.
10. Run static analysis.
11. Run dynamic analysis for fixed timeout.
12. Capture process, file, registry, and network activity.
13. Generate report.
14. Attach report to TheHive case.
15. Destroy VM.
16. Delete temporary disk.
17. Return result to Shuffle.
```

---

## 9. Static Analysis

Static analysis should run before executing the file.

Collect:

- File name
- File size
- MD5
- SHA1
- SHA256
- File type
- PE metadata
- Strings
- YARA matches
- Import table
- Packer detection
- VirusTotal summary

Example static output:

```json
{
  "file_name": "update_helper.exe",
  "sha256": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
  "file_type": "PE32 executable",
  "yara_matches": ["EICAR_Test_File"],
  "vt_malicious": 65,
  "vt_suspicious": 0
}
```

---

## 10. Dynamic Analysis

Dynamic analysis runs the sample inside the temporary VM.

Collect:

- Process tree
- Child processes
- Command lines
- Registry modifications
- File writes
- File deletions
- Dropped files
- DNS queries
- HTTP/HTTPS connections
- TCP/UDP connections
- Screenshots if GUI mode is enabled
- PCAP file

Recommended timeout:

```text
3 to 10 minutes
```

For the first version, use:

```text
5 minutes
```

---

## 11. AI Report Generation

The AI should receive structured analysis results, not raw uncontrolled access.

Input to AI:

```json
{
  "case_id": "SOC-...",
  "sample": {
    "file_name": "update_helper.exe",
    "file_path": "C:\\Users\\win10-victim\\AppData\\Roaming\\MicrosoftEdge\\update_helper.exe",
    "sha256": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"
  },
  "static_analysis": {},
  "dynamic_analysis": {},
  "network_analysis": {},
  "virustotal": {},
  "wazuh_alert": {}
}
```

Output report should include:

```text
# SOCaaS AI Sandbox Malware Report

## Executive Summary
## Sample Information
## Wazuh Context
## VirusTotal Summary
## Static Analysis
## Dynamic Behavior
## Network Activity
## Persistence Indicators
## Dropped Files
## MITRE ATT&CK Mapping
## Risk Assessment
## Recommended Analyst Actions
## IOCs
## Artifacts Collected
```

---

## 12. Local Orchestrator API

### Endpoint

```text
POST /analyze
```

Example request from Shuffle:

```json
{
  "case_id": "SOC-20260515-130352-554-eicar-malware-1778807852",
  "alert_type": "malware",
  "agent": "win10-victim",
  "agent_ip": "192.168.122.98",
  "file_name": "update_helper.exe",
  "file_path": "C:\\Users\\win10-victim\\AppData\\Roaming\\MicrosoftEdge\\update_helper.exe",
  "file_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
  "rule_id": "554",
  "rule_desc": "EICAR test file detected - known malware hash"
}
```

Example response:

```json
{
  "status": "completed",
  "case_id": "SOC-20260515-130352-554-eicar-malware-1778807852",
  "sandbox_vm": "sandbox-SOC-20260515-130352",
  "report_path": "/opt/socaas-sandbox/reports/SOC-20260515-130352.md",
  "summary": "EICAR test file detected. No persistence or C2 behavior observed.",
  "artifacts": [
    "sandbox_report.md",
    "process_tree.json",
    "network.pcap",
    "filesystem_changes.json"
  ]
}
```

---

## 13. Shuffle Workflow Design

Current workflow:

```text
Webhook_1
  -> Normalize_SOC_Alert
  -> Build_VirusTotal_Target
  -> Virustotal_v3
  -> Generate_AI_Recommended_Actions
  -> Build_Context_TheHive_Email_Body
  -> Build_Telegram_Payload
  -> Send_Telegram_Notification
  -> Send_Email_Notification
  -> Create_TheHive_Case
  -> Final_Response
```

Recommended workflow with sandbox:

```text
Webhook_1
  -> Normalize_SOC_Alert
  -> Build_VirusTotal_Target
  -> Virustotal_v3
  -> Generate_AI_Recommended_Actions
  -> Build_Context_TheHive_Email_Body
  -> Request_AI_Sandbox_Analysis
  -> Attach_Sandbox_Report_To_TheHive
  -> Build_Telegram_Payload
  -> Send_Telegram_Notification
  -> Send_Email_Notification
  -> Create_TheHive_Case / Update_TheHive_Case
  -> Final_Response
```

Important: If the case is created after the sandbox step, the sandbox report cannot be attached immediately. Better design:

```text
Create_TheHive_Case first
  -> Request_AI_Sandbox_Analysis
  -> Attach_Sandbox_Report_To_TheHive
```

Recommended final order:

```text
Webhook_1
  -> Normalize_SOC_Alert
  -> Build_VirusTotal_Target
  -> Virustotal_v3
  -> Generate_AI_Recommended_Actions
  -> Build_Context_TheHive_Email_Body
  -> Create_TheHive_Case
  -> Request_AI_Sandbox_Analysis
  -> Attach_Sandbox_Report_To_TheHive
  -> Build_Telegram_Payload
  -> Send_Telegram_Notification
  -> Send_Email_Notification
  -> Final_Response
```

---

## 14. Shuffle Node: Request_AI_Sandbox_Analysis

This node should be an HTTP POST node.

URL:

```text
http://192.168.122.1:5055/analyze
```

Headers:

```json
{
  "Content-Type": "application/json",
  "X-SOCaaS-Sandbox-Secret": "CHANGE_ME"
}
```

Body:

```json
{
  "case_id": "$Build_Context_TheHive_Email_Body.message.case_id",
  "alert_type": "$Build_Context_TheHive_Email_Body.message.alert_type",
  "severity": "$Build_Context_TheHive_Email_Body.message.severity",
  "score": "$Build_Context_TheHive_Email_Body.message.score",
  "agent": "$Build_Context_TheHive_Email_Body.message.agent",
  "agent_id": "$Build_Context_TheHive_Email_Body.message.agent_id",
  "agent_ip": "$Build_Context_TheHive_Email_Body.message.agent_ip",
  "rule_id": "$Build_Context_TheHive_Email_Body.message.rule_id",
  "rule_desc": "$Build_Context_TheHive_Email_Body.message.rule_desc",
  "file_name": "$Build_Context_TheHive_Email_Body.message.file_name",
  "file_path": "$Build_Context_TheHive_Email_Body.message.file_path",
  "file_hash": "$Build_Context_TheHive_Email_Body.message.file_hash",
  "md5": "$Build_Context_TheHive_Email_Body.message.md5",
  "sha1": "$Build_Context_TheHive_Email_Body.message.sha1",
  "sha256": "$Build_Context_TheHive_Email_Body.message.sha256",
  "process_name": "$Build_Context_TheHive_Email_Body.message.process_name",
  "command_line": "$Build_Context_TheHive_Email_Body.message.command_line",
  "username": "$Build_Context_TheHive_Email_Body.message.username",
  "vt_target_type": "$Build_Context_TheHive_Email_Body.message.vt_target_type",
  "vt_target_value": "$Build_Context_TheHive_Email_Body.message.vt_target_value",
  "vt_malicious": "$Build_Context_TheHive_Email_Body.message.vt_malicious",
  "vt_suspicious": "$Build_Context_TheHive_Email_Body.message.vt_suspicious"
}
```

---

## 15. Skip Logic

The sandbox orchestrator should skip non-malware alerts.

Pseudo-logic:

```python
if alert_type != "malware":
    return {
        "status": "skipped",
        "reason": "Alert type is not malware"
    }

if not file_hash and not file_path:
    return {
        "status": "skipped",
        "reason": "No malware sample path or hash available"
    }
```

This means scans, C2, authentication, and exfiltration events will not create sandbox VMs unless you explicitly allow them.

---

## 16. TheHive Attachment Design

The sandbox service can either:

### Option A: Attach directly to TheHive

The orchestrator receives the case ID and uploads the report to TheHive itself.

Pros:

- Less Shuffle complexity.
- The orchestrator controls all sandbox artifacts.

Cons:

- The orchestrator needs TheHive API credentials.

### Option B: Return report to Shuffle

The orchestrator returns a report URL/path, and Shuffle attaches it.

Pros:

- Shuffle remains responsible for case updates.

Cons:

- More workflow steps.
- Shuffle may need file upload handling.

Recommended first version:

```text
Orchestrator attaches directly to TheHive.
```

---

## 17. Security Controls

Minimum safety controls:

1. Isolated sandbox network.
2. No direct access to SOC network.
3. No shared clipboard.
4. No shared folders except controlled transfer directory.
5. VM destroyed after every run.
6. Disk deleted after every run.
7. Hard timeout for analysis.
8. API secret between Shuffle and orchestrator.
9. Sample size limit.
10. Only allow malware alerts to trigger analysis.
11. Store reports outside the VM.
12. Never let AI execute arbitrary host commands.
13. Log every sandbox action.

---

## 18. Directory Layout

Recommended host directory layout:

```text
/opt/socaas-sandbox/
  orchestrator/
    app.py
    config.yaml
    runners/
      windows_runner.py
      static_analysis.py
      dynamic_analysis.py
      report_generator.py
  templates/
    win10-sandbox-golden.qcow2
  samples/
    incoming/
    quarantined/
  runs/
    SOC-CASEID/
      sample/
      static/
      dynamic/
      network/
      artifacts/
      logs/
  reports/
    SOC-CASEID.md
    SOC-CASEID.pdf
  yara/
    rules.yar
  logs/
    orchestrator.log
```

---

## 19. Implementation Steps

### Step 1: Prepare the golden VM

1. Create Windows 10 VM.
2. Install analysis tools.
3. Install sandbox guest runner.
4. Disable unnecessary services.
5. Configure Sysmon.
6. Configure PowerShell logging.
7. Take snapshot or shut down cleanly.
8. Save as golden image.

### Step 2: Create isolated network

Create `sandbox-net` in libvirt.

Use isolated mode first.

### Step 3: Build orchestrator API

Create a local FastAPI service:

```text
POST /analyze
GET /health
```

### Step 4: Implement VM lifecycle

Implement:

```text
create_vm()
wait_for_vm()
transfer_sample()
run_analysis()
collect_results()
destroy_vm()
```

### Step 5: Implement static analysis

Add:

- Hash calculation
- File type
- Strings
- YARA
- Metadata extraction

### Step 6: Implement dynamic analysis

Add:

- Process monitoring
- File monitoring
- Registry monitoring
- Network capture
- DNS/HTTP fake services

### Step 7: Implement report generation

Generate Markdown first.

Later add PDF export.

### Step 8: Attach report to TheHive

Add direct TheHive API integration or return report path to Shuffle.

### Step 9: Add Shuffle node

Add `Request_AI_Sandbox_Analysis` after TheHive case creation.

### Step 10: Test with EICAR

Use safe malware simulation first.

---

## 20. Testing Plan

### Test 1: Orchestrator health

```bash
curl -sS http://192.168.122.1:5055/health
```

Expected:

```json
{
  "status": "ok"
}
```

### Test 2: Manual sandbox request

```bash
curl -sS -X POST http://192.168.122.1:5055/analyze \
  -H "Content-Type: application/json" \
  -H "X-SOCaaS-Sandbox-Secret: CHANGE_ME" \
  -d '{
    "case_id": "SOC-TEST-EICAR-001",
    "alert_type": "malware",
    "agent": "win10-victim",
    "agent_ip": "192.168.122.98",
    "rule_id": "554",
    "rule_desc": "EICAR test file detected - known malware hash",
    "file_name": "eicar.com",
    "file_path": "C:\\Users\\win10-victim\\Downloads\\eicar.com",
    "file_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"
  }'
```

Expected:

```json
{
  "status": "completed",
  "case_id": "SOC-TEST-EICAR-001",
  "report_path": "/opt/socaas-sandbox/reports/SOC-TEST-EICAR-001.md"
}
```

### Test 3: Trigger malware workflow from CLI

```bash
curl -sS -X POST http://192.168.122.1:30001/hooks/wazuh \
  -H "X-SOCaaS-Webhook-Secret: Hu2sjS8pd2CFpWixOYX0" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "eicar-malware-'"$(date +%s)"'",
    "source": "wazuh",
    "manager": {"name": "socaas-wazuh-manager-0"},
    "rule": {
      "id": "554",
      "level": 12,
      "description": "EICAR test file detected - known malware hash",
      "groups": ["malware", "eicar", "windows"]
    },
    "agent": {
      "id": "002",
      "name": "win10-victim",
      "ip": "192.168.122.98"
    },
    "location": "EventChannel",
    "data": {
      "file_name": "eicar.com",
      "file_path": "C:\\Users\\win10-victim\\Downloads\\eicar.com",
      "file_hash": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
      "sha256": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
      "process_name": "powershell.exe",
      "username": "win10-victim\\khalil",
      "action": "detected"
    },
    "full_log": "EICAR test file detected on win10-victim at C:\\Users\\win10-victim\\Downloads\\eicar.com"
  }'
```

Expected:

```text
1. Shuffle workflow starts.
2. Alert type becomes malware.
3. VirusTotal checks file hash.
4. TheHive case is created.
5. Sandbox analysis is requested.
6. Temporary VM is created.
7. Report is generated.
8. Report is attached to TheHive.
9. Telegram and email are sent.
10. VM is destroyed.
```

### Test 4: Verify VM cleanup

```bash
virsh list --all | grep sandbox-
ls -lh /var/lib/libvirt/images/ | grep sandbox-
```

Expected after cleanup:

```text
No sandbox VM remains.
No temporary sandbox qcow2 remains.
```

### Test 5: Verify TheHive attachment

Open the TheHive case and verify:

- Sandbox report is attached.
- Tags include `sandbox-analysis`.
- Report summary is visible.
- IOCs are listed.
- Recommended actions are included.

---

## 21. First Version Scope

Keep the first version simple:

```text
Supported alert type: malware only
Supported OS: Windows sandbox only
Runtime: 5 minutes
Network: isolated / fake internet only
Report format: Markdown
Attachment: direct to TheHive or returned to Shuffle
Cleanup: mandatory after every run
```

Do not start with real malware from the internet. Start with EICAR and internal test samples.

---

## 22. Future Improvements

Later features:

- Linux sandbox profile
- Office macro sandbox profile
- PowerShell-only sandbox profile
- Memory dump capture
- Screenshots
- CAPE/Cuckoo integration
- Suricata/Zeek analysis of PCAP
- Automatic YARA generation
- Automatic Sigma rule suggestion
- AI-generated remediation checklist
- AI-generated threat summary for customer reports
- Analyst approval before dynamic execution
- Multi-tenant sandbox isolation

---

## 23. Final Recommended Flow

```text
Malware alert detected
        |
        v
Normalize + enrich with VirusTotal
        |
        v
Create TheHive case
        |
        v
Trigger AI Sandbox Orchestrator
        |
        v
Create temporary VM from golden image
        |
        v
Transfer sample
        |
        v
Static + dynamic analysis
        |
        v
AI report generation
        |
        v
Attach report to TheHive
        |
        v
Destroy VM and delete disk
        |
        v
Notify analyst
```

This design gives SOCaaS an automated malware triage capability while keeping the dangerous execution isolated, repeatable, and disposable.
