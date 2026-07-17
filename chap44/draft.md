# Chapter 4 - Implementation and Validation of the SOCaaS Platform

  ## 4.1 Introduction

  This chapter presents the implementation and validation of the SOCaaS platform, an open-source, cloud-native Security Operations
  Center deployed on Kubernetes. The objective of this chapter is to demonstrate how the proposed architecture was transformed from
  design into a working security platform capable of detecting threats, enriching alerts, automating response workflows, creating
  investigation cases, notifying analysts, and supporting malware analysis through an AI Sandbox.

  The implementation combines multiple open-source security components, including Wazuh SIEM, Shuffle SOAR, TheHive case management,
  and a custom Pipeline Gateway. These components are deployed in a Kubernetes cluster composed of one control-plane node and two
  worker nodes. The platform is validated using controlled attack simulations and malware analysis scenarios performed inside a
  laboratory environment.

  A major contribution of this chapter is the integration of an AI Sandbox for malware triage. Unlike traditional alerting pipelines
  that only notify analysts of suspicious activity, SOCaaS extends the investigation process by automatically analyzing suspicious
  files in a temporary isolated VM, extracting indicators of compromise, reconstructing behavior, and generating an analyst-readable
  PDF report using DeepSeek-V4-Pro. This feature is particularly valuable for small and medium-sized enterprises, where dedicated
  malware reverse engineering teams are often unavailable.

  ## 4.2 Overview of the Kubernetes Cluster

  The SOCaaS platform was deployed on a Kubernetes cluster hosted inside a virtualized laboratory environment. The virtualization layer
  was implemented using KVM/QEMU with libvirt on a Parrot OS host. All virtual machines were connected through the default libvirt
  virtual bridge virbr0, using the subnet 192.168.122.0/24.

  The Kubernetes cluster uses a single control-plane node, k8s-master, and two worker nodes. The first worker node, k8s-worker1, hosts
  SIEM-related workloads, mainly Wazuh. The second worker node, k8s-worker2, hosts SOAR, case management, search, storage, and
  orchestration components, including Shuffle, TheHive, Cassandra, MinIO, Elasticsearch, Redis, and OpenSearch.

  External access to selected services is provided through HAProxy and Kubernetes NodePort services. This allows dashboards, webhooks,
  and service endpoints to be reached from the laboratory network while keeping the deployment aligned with Kubernetes service
  abstraction.

  Two victim endpoints were included in the environment to validate detection and response. The Linux endpoint victim-01 was used for
  Linux-based detection scenarios, while win10-victim was used for Windows process, malware, and endpoint telemetry validation.

  ┌──────────────────────────┬────────────────┬─────────────────┬──────────────────────────────────────┐
  │ Component                │       Hostname │      IP Address │ Role                                 │
  ├──────────────────────────┼────────────────┼─────────────────┼──────────────────────────────────────┤
  │ Hypervisor host          │ Parrot OS host │   192.168.122.1 │ KVM/QEMU and libvirt host            │
  │ Kubernetes control-plane │     k8s-master │  192.168.122.10 │ Single Kubernetes control-plane node │
  │ Kubernetes worker        │    k8s-worker1 │  192.168.122.11 │ SIEM workloads                       │
  │ Kubernetes worker        │    k8s-worker2 │  192.168.122.12 │ SOAR and TheHive workloads           │
  │ Linux victim endpoint    │      victim-01 │ 192.168.122.180 │ Linux monitored endpoint             │
  │ Windows victim endpoint  │   win10-victim │  192.168.122.98 │ Windows monitored endpoint           │
  └──────────────────────────┴────────────────┴─────────────────┴──────────────────────────────────────┘

  > Figure 4.1 - SOCaaS Kubernetes Cluster Architecture

  Image description: The figure should show the Parrot OS host running KVM/QEMU and libvirt, with the virbr0 network connecting the
  Kubernetes nodes and victim endpoints. The diagram should show one control-plane node, k8s-master, connected to two worker nodes.
  k8s-worker1 should be labeled as hosting Wazuh SIEM workloads, while k8s-worker2 should be labeled as hosting Shuffle SOAR, Pipeline
  Gateway, TheHive, Cassandra, MinIO, Elasticsearch, Redis, and OpenSearch. The Linux and Windows victim endpoints should appear as
  monitored endpoints sending telemetry to Wazuh agents.

  ## 4.3 Deployment of the Kubernetes Cluster

  The Kubernetes cluster was deployed using Kubernetes version v1.28.15, with containerd 2.2.1 as the container runtime and Calico
  v3.28.5 as the Container Network Interface. The deployment followed a controlled sequence to ensure that the cluster was reproducible
  and suitable for hosting security workloads.

  First, containerd was installed and configured on all Kubernetes nodes. The runtime was selected because it is widely used in
  Kubernetes environments and provides a lightweight, standards-based container execution layer. After configuring the runtime, the
  Kubernetes packages kubeadm, kubelet, and kubectl were installed on the control-plane and worker nodes.

  The cluster was initialized on k8s-master using kubeadm init. This process created the single Kubernetes control-plane node
  responsible for the API server, scheduler, controller manager, and cluster coordination. After initialization, Calico was deployed to
  provide pod networking and network policy support across the cluster.

  The worker nodes k8s-worker1 and k8s-worker2 were then joined to the cluster using the join command generated during control-plane
  initialization. Once the nodes joined successfully, cluster status was verified using Kubernetes commands to confirm that all nodes
  were in the Ready state and that Calico system pods were running correctly.

  > Figure 4.2 - Containerd Runtime Version

  Image description: Screenshot showing the installed containerd version on one of the Kubernetes nodes, confirming that containerd
  2.2.1 is used as the container runtime.

  > Figure 4.3 - Kubernetes Packages Installed

  Image description: Screenshot showing the installed Kubernetes packages, including kubeadm, kubelet, and kubectl, with version
  v1.28.15.

  > Figure 4.4 - Kubernetes Control-Plane Initialization

  Image description: Screenshot showing the successful execution of kubeadm init on k8s-master, including the generated worker join
  command.

  > Figure 4.5 - Calico Pods Running

  Image description: Screenshot showing Calico pods running in the Kubernetes system namespace, validating that the Kubernetes
  networking layer is active.

  > Figure 4.6 - Worker Nodes Joined to the Cluster

  Image description: Screenshot showing k8s-worker1 and k8s-worker2 successfully joined to the Kubernetes cluster.

  > Figure 4.7 - Kubernetes Cluster Status

  Image description: Screenshot showing all Kubernetes nodes in the Ready state, including k8s-master, k8s-worker1, and k8s-worker2.

  ## 4.4 Deployment of SOCaaS Security Tools

  The SOCaaS security platform was deployed using Kubernetes manifests and Helm packaging. Kubernetes namespaces were used to separate
  platform components logically and operationally. The namespace socaas-system stores Helm release state, socaas-siem hosts Wazuh SIEM
  components, socaas-soar hosts Shuffle, Pipeline Gateway, Redis, and OpenSearch, and socaas-thehive hosts TheHive, Cassandra, MinIO,
  and Elasticsearch.

  This separation improves clarity, troubleshooting, and operational control. Each namespace groups related services, configuration,
  secrets, storage, and network exposure according to its role in the SOCaaS pipeline.

  ### 4.4.1 Wazuh SIEM Deployment

  Wazuh was deployed as the SIEM layer of SOCaaS in the socaas-siem namespace. The Wazuh deployment consists of Wazuh Manager 4.8.2,
  Wazuh Indexer 4.8.2, and Wazuh Dashboard 4.8.2. The Wazuh workloads were assigned to k8s-worker1, separating SIEM processing from
  SOAR and case management workloads hosted on the second worker node.

  The Wazuh Manager receives security telemetry from Wazuh agents installed on the monitored endpoints. The Linux agent was installed
  on victim-01, and the Windows agent was installed on win10-victim. These agents collect endpoint events, file integrity monitoring
  data, Windows security events, process activity, network-related events, and malware-related alerts.

  Custom Wazuh rules were implemented to support SOCaaS-specific detection needs. These include UFW and port scan detection, File
  Integrity Monitoring malware detection, Windows Defender malware detection, and Windows process and network event detection. These
  rules transform raw endpoint activity into actionable alerts for the SOCaaS pipeline.

  To integrate Wazuh with the automation layer, a Wazuh Alert Forwarder sidecar was implemented. This component reads Wazuh alerts and
  forwards them to the Pipeline Gateway. This design avoids direct coupling between Wazuh and Shuffle, allowing SOCaaS to normalize,
  enrich, deduplicate, and validate alerts before they enter the SOAR workflow.

  > Figure 4.8 - Wazuh Pods Running

  Image description: Screenshot showing Wazuh Manager, Wazuh Indexer, and Wazuh Dashboard pods running in the socaas-siem namespace.

  > Figure 4.9 - Wazuh Dashboard

  Image description: Screenshot of the Wazuh Dashboard showing the SOCaaS environment and monitored agents.

  > Figure 4.10 - Wazuh Agent Status

  Image description: Screenshot showing the Linux and Windows Wazuh agents connected to the Wazuh Manager.

  > Figure 4.11 - Wazuh Alerts

  Image description: Screenshot showing generated Wazuh alerts from validation scenarios, including malware, scan, or suspicious
  endpoint activity.

  ### 4.4.2 Pipeline Gateway Deployment

  The Pipeline Gateway is a custom Python 3.12 service that acts as the integration layer between Wazuh, Shuffle SOAR, and TheHive. It
  receives alerts from the Wazuh Alert Forwarder through the /hooks/wazuh endpoint and validates each request using a webhook secret.
  This validation prevents unauthorized systems from injecting alerts into the SOCaaS automation workflow.

  After validation, the Pipeline Gateway parses the incoming alert and extracts observables such as IP addresses, domains, hashes,
  URLs, ports, and process names. These observables are then normalized into a structured alert format. This deterministic
  normalization step is important because it ensures that downstream systems receive clean and explicit security context before AI-
  assisted processing is used.

  The gateway also performs VirusTotal enrichment where applicable. Public IP addresses, domains, hashes, and URLs can be enriched to
  provide additional reputation and threat intelligence context. However, private IP addresses such as 192.168.122.1 are treated
  carefully because they cannot be meaningfully scored by external reputation services.

  To reduce alert fatigue, the Pipeline Gateway implements alert deduplication using a 300-second TTL cache. Repeated alerts with the
  same essential characteristics are suppressed or grouped so that Shuffle and TheHive receive fewer duplicate events. This is
  especially useful during noisy simulations such as port scans, where many raw events can be generated in a short period.

  The resulting normalized alert is forwarded to Shuffle for automated triage, while context suitable for case creation is prepared for
  TheHive.

  > Figure 4.12 - Pipeline Gateway Pod and Service

  Image description: Screenshot showing the Pipeline Gateway pod and Kubernetes service running in the socaas-soar namespace.

  > Figure 4.13 - Pipeline Gateway Health Check

  Image description: Screenshot showing a successful health check response from the Pipeline Gateway service.

  > Figure 4.14 - Sample Normalized Alert

  Image description: Screenshot or JSON excerpt showing a normalized alert produced by the Pipeline Gateway, with observables extracted
  from a Wazuh alert.

  > Figure 4.15 - Deduplication Evidence

  Image description: Screenshot showing repeated raw alerts being reduced or grouped by the Pipeline Gateway deduplication mechanism.

  ### 4.4.3 Shuffle SOAR Deployment

  Shuffle SOAR was deployed in the socaas-soar namespace and provides the automation layer of SOCaaS. The deployment includes Shuffle
  Frontend, Backend, Orborus, Redis, and OpenSearch. Shuffle receives normalized alerts from the Pipeline Gateway and executes the
  SOCaaS incident triage workflow.

  The workflow implemented for this project is named SOCaaS Wazuh Alert Triage. It automates the main response steps required after an
  alert is received. The workflow begins with a webhook trigger and proceeds through normalization, enrichment, AI-assisted
  recommendations, notification, and case creation.

  The main workflow actions are:

  ┌──────┬──────────────────────────────────┬─────────────────────────────────────────────────────────┐
  │ Step │ Workflow Action                  │ Purpose                                                 │
  ├──────┼──────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │    1 │ Webhook_1                        │ Receives the normalized alert from the Pipeline Gateway │
  │    2 │ Normalize_SOC_Alert              │ Ensures alert fields are structured consistently        │
  │    3 │ Virustotal_v3                    │ Enriches extracted observables using VirusTotal         │
  │    4 │ Generate_AI_Recommended_Actions  │ Produces structured analyst recommendations             │
  │    5 │ Build_Context_TheHive_Email_Body │ Builds detailed investigation context                   │
  │    6 │ Send_Telegram_Notification       │ Sends a short alert to analysts                         │
  │    7 │ Send_Email_Notification          │ Sends richer alert context by email                     │
  │    8 │ Create_TheHive_Case              │ Creates a case in TheHive                               │
  │    9 │ Final_Response                   │ Returns the final workflow status                       │
  └──────┴──────────────────────────────────┴─────────────────────────────────────────────────────────┘

  The workflow was designed so that Telegram receives short, high-priority alerts, while TheHive and email receive richer context. This
  prevents mobile notifications from becoming too long while preserving full evidence for formal investigation.

  > Figure 4.16 - Shuffle Pods Running

  Image description: Screenshot showing Shuffle Frontend, Backend, Orborus, Redis, and OpenSearch pods running in the socaas-soar
  namespace.

  > Figure 4.17 - Shuffle Dashboard

  Image description: Screenshot of the Shuffle dashboard showing the SOCaaS automation environment.

  > Figure 4.18 - SOCaaS Wazuh Alert Triage Workflow Canvas

  Image description: Screenshot of the Shuffle workflow canvas showing the full automation chain from webhook reception to TheHive case
  creation.

  > Figure 4.19 - Workflow Execution Result

  Image description: Screenshot showing a successful execution of the SOCaaS Wazuh Alert Triage workflow.

  ### 4.4.4 TheHive Case Management Deployment

  TheHive was deployed in the socaas-thehive namespace as the case management component of SOCaaS. The deployed version is TheHive
  5.3.11-1. TheHive provides the analyst-facing investigation interface where alerts are transformed into cases, observables, tasks,
  and evidence records.

  TheHive was deployed with Cassandra, Elasticsearch 7.10.2, and MinIO. Cassandra acts as the primary database and stores TheHive case
  data. Elasticsearch provides the search index used to query and retrieve cases efficiently. MinIO provides object and file storage,
  including attachments and generated reports.

  The organization configured for the platform is socaas. The integration user used by Shuffle is socaas-shuffle@thehive.local. API
  calls to TheHive require the X-Organisation: socaas header to ensure that actions are executed inside the correct organization
  context.

  This deployment allows Shuffle to create cases automatically when relevant Wazuh alerts are received. Cases can include alert
  summaries, observables, enrichment results, AI recommendations, and references to sandbox-generated reports.

  > Figure 4.20 - TheHive Pods Running

  Image description: Screenshot showing TheHive, Cassandra, MinIO, and Elasticsearch pods running in the socaas-thehive namespace.

  > Figure 4.21 - Elasticsearch Backend Status

  Image description: Screenshot showing Elasticsearch running as the search backend for TheHive.

  > Figure 4.22 - TheHive Dashboard

  Image description: Screenshot of the TheHive dashboard inside the socaas organization.

  > Figure 4.23 - Created TheHive Case

  Image description: Screenshot showing a case automatically created by the SOCaaS workflow from a Wazuh alert.

  ## 4.5 Implementation of the SOCaaS Helm Chart

  To improve repeatability and simplify deployment, the SOCaaS platform was packaged using Helm. The Helm chart is named socaas and
  groups Kubernetes manifests by platform component. This approach supports reproducible deployments, easier updates, and a client-
  ready packaging model.

  Helm was selected because SOCaaS consists of multiple services, namespaces, deployments, configuration files, services, and
  integration settings. Managing these resources manually would increase deployment complexity and make the platform harder to
  reproduce. With Helm, the SOCaaS deployment can be installed, upgraded, or removed using a controlled release workflow.

  The chart structure separates templates according to function. SIEM resources, SOAR resources, TheHive resources, service
  definitions, configuration maps, and supporting Kubernetes objects are organized in the chart templates folder. The socaas-system
  namespace stores Helm release state, allowing deployment status to be tracked consistently.

  > Figure 4.24 - SOCaaS Helm Chart Structure

  Image description: Screenshot showing the socaas Helm chart directory structure, including chart metadata, values, and template
  files.

  > Figure 4.25 - SOCaaS Templates Folder

  Image description: Screenshot showing the Kubernetes manifest templates grouped by SOCaaS component.

  > Figure 4.26 - Helm Deployment Result

  Image description: Screenshot showing the successful Helm installation or upgrade of the socaas chart.

  ## 4.6 End-to-End Detection and Response Pipeline

  The SOCaaS platform implements an end-to-end detection and response pipeline that connects endpoint telemetry to automated triage and
  case management. The pipeline begins when an attacker action, malware execution, or reconnaissance scan affects a monitored endpoint.
  The endpoint Wazuh agent collects the relevant telemetry and forwards it to the Wazuh Manager.

  Wazuh evaluates the event using built-in and custom detection rules. When an alert is generated, it is written to Wazuh alert output
  and forwarded by the Wazuh Alert Forwarder sidecar to the Pipeline Gateway. The Pipeline Gateway validates the request, extracts
  observables, normalizes the alert, enriches available indicators, and deduplicates repeated alerts using a 300-second TTL cache.

  After processing, the normalized alert is forwarded to Shuffle SOAR. Shuffle executes the SOCaaS Wazuh Alert Triage workflow, which
  enriches the alert further, generates AI-assisted recommendations, sends notifications, and creates a TheHive case. Telegram receives
  a short notification suitable for rapid awareness, while email and TheHive receive richer context for investigation.

  When the alert contains or references a suspicious file, the AI Sandbox can be invoked. The sandbox analyzes the sample inside a
  temporary isolated VM and generates a report that can be attached or referenced in TheHive. This extends the SOCaaS workflow from
  detection and notification to malware understanding and first-level reverse engineering support.

  The complete flow is:

  Attacker, malware, or scan -> victim endpoint -> Wazuh agent -> Wazuh Manager -> Wazuh alerts -> Alert Forwarder -> Pipeline Gateway
  -> Shuffle SOAR -> Telegram and email notification -> TheHive case -> optional AI Sandbox analysis.

  > Figure 4.27 - SOCaaS End-to-End Detection and Response Pipeline

  Image description: Diagram showing the complete SOCaaS pipeline from attacker activity on victim endpoints to Wazuh detection,
  Pipeline Gateway normalization and enrichment, Shuffle SOAR automation, Telegram and email notification, TheHive case creation, and
  optional AI Sandbox malware analysis.

  ## 4.7 AI-Assisted Alert Triage

  AI-assisted triage was implemented to support analysts during incident response. The AI recommendation node in the Shuffle workflow
  receives normalized structured context and produces recommended actions, a concise summary of the evidence, and guidance for
  containment, investigation, and escalation.

  The AI component is used as an assistant, not as a final decision-maker. Deterministic parsing, observable extraction, and
  normalization are performed before the AI step. This design reduces the risk of hallucinated observables because the AI receives
  already extracted fields rather than being asked to infer raw evidence without structure.

  The AI output enriches TheHive and email context, where analysts can review the recommendation alongside raw alert evidence and
  enrichment results. Telegram notifications remain intentionally short and are used only for rapid awareness. Detailed explanations,
  observables, and response recommendations are stored in TheHive and email, where they are more appropriate for analyst review.

  The main value of the AI-assisted triage layer is that it accelerates the first interpretation of alerts. Instead of beginning with
  raw logs only, analysts receive a structured starting point that helps them decide whether to contain a host, block an indicator,
  inspect related events, or escalate the case.

  ## 4.8 AI Sandbox Malware Analysis

  Manual malware analysis is one of the most time-consuming activities in incident response. Static analysis, reverse engineering,
  behavioral interpretation, IOC extraction, and report writing require specialized expertise. In many small and medium-sized
  enterprises, this expertise is limited or unavailable. As a result, suspicious files may delay the investigation process, even when
  the detection pipeline is functioning correctly.

  To address this limitation, SOCaaS includes an AI Sandbox malware analysis capability. The AI Sandbox receives suspicious files from
  alert context and analyzes them in a temporary isolated VM. The sandbox follows a disposable lifecycle: golden image -> temporary VM
  clone -> analyze sample -> generate report -> destroy VM -> delete disk. This design ensures that the analysis environment is not
  reused after handling a potentially malicious file.

  The sandbox performs file identification, hashing, string extraction, static behavior analysis, suspicious API call identification,
  IOC extraction, and logic reconstruction. Where appropriate, dynamic analysis can also be performed inside the temporary isolated VM.
  The resulting evidence is passed to DeepSeek-V4-Pro, which generates an analyst-readable malware analysis report.

  The generated report includes file identification, hashes, suspicious strings, static behavior, reconstructed logic or pseudocode,
  IOCs, MITRE ATT&CK mapping, risk verdict, and recommended analyst actions. The report can be attached to or referenced from TheHive,
  allowing analysts to continue the investigation using structured evidence rather than starting from the malware sample manually.

  The AI Sandbox lifecycle is:

  Wazuh malware alert -> Shuffle malware workflow -> AI Sandbox Orchestrator -> Temporary isolated VM -> Static/Dynamic Analysis ->
  DeepSeek-V4-Pro report -> TheHive case -> VM destroyed after analysis.

  The AI Sandbox is therefore not only an additional tool but an investigation accelerator. It reduces the time needed to understand
  malware behavior and provides first-level malware triage for organizations that cannot maintain a dedicated reverse engineering team.

  > Figure 4.28 - AI Sandbox Architecture

  Image description: Diagram showing the AI Sandbox connected to Shuffle and TheHive, with an orchestrator managing temporary isolated
  VM creation, sample analysis, report generation, and VM destruction.

  > Figure 4.29 - Sandbox Orchestrator Request

  Image description: Screenshot showing a sandbox analysis request submitted from the SOCaaS workflow to the AI Sandbox Orchestrator.

  > Figure 4.30 - Temporary VM Lifecycle

  Image description: Diagram showing the sandbox lifecycle from golden image to temporary VM clone, sample analysis, report generation,
  VM destruction, and disk deletion.

  > Figure 4.31 - Generated PDF Report First Page

  Image description: Screenshot of the first page of the AI Sandbox PDF report generated for the malware analysis case study.

  > Figure 4.32 - TheHive Case with Sandbox Report

  Image description: Screenshot showing a TheHive case containing or referencing the AI Sandbox malware analysis report.

  ## 4.9 AI Sandbox Case Study: Password File Exfiltration Script

  A controlled malware sample was used to validate the AI Sandbox. The sample was a Python script created specifically for the
  laboratory environment. It was designed to search the local filesystem recursively for files whose names contain the word password,
  read matching files, and send the collected content to a command-and-control listener at 192.168.122.1:4444.

  The original source code is not reproduced in this thesis. The sample is described only at a behavioral level to avoid including
  harmful implementation details. Detailed evidence and the generated sandbox report are provided in Appendix C.

  The sample was submitted to the AI Sandbox without exposing its source code in the chapter. The sandbox identified the file as a
  Python-based credential harvesting and data exfiltration tool. It extracted the core behavior of the sample and reconstructed the
  same logic as the original script. The recovered behavior included recursive directory traversal, filename matching based on the word
  password, file reading, TCP exfiltration, the destination 192.168.122.1:4444, and a payload format containing file path and file
  content.

  The generated report marked the sample as malicious. It extracted indicators of compromise including the SHA256 hash, the IP address
  192.168.122.1, TCP port 4444, the searched filename pattern containing password, and a network signature related to outbound
  exfiltration activity.

  The report also recommended practical analyst actions. These included blocking the extracted IOCs, investigating the C2 listener,
  scoping the affected host, hunting for possible data loss, rotating exposed credentials, preserving forensic evidence, and enforcing
  policies that prevent plaintext password files from being stored on endpoints.

  The most important validation result is that the sandbox report reconstructed the same logic as the original script. This
  demonstrates that the AI Sandbox can provide useful first-level malware triage by recovering behavior, extracting IOCs, and producing
  an analyst-readable report. The full five-page AI Sandbox report is provided in Appendix C.

  > Figure 4.33 - Sample Submission to AI Sandbox

  Image description: Screenshot showing the controlled malware sample submitted to the AI Sandbox for analysis.

  > Figure 4.34 - Static Analysis Summary

  Image description: Screenshot showing the AI Sandbox static analysis summary, including file type, hashes, strings, and suspicious
  behavior.

  > Figure 4.35 - Reversed Logic or Pseudocode Output

  Image description: Screenshot showing the sandbox report section where the malware logic is reconstructed in descriptive pseudocode.

  > Figure 4.36 - IOC Extraction

  Image description: Screenshot showing extracted IOCs such as SHA256 hash, destination IP address, TCP port, searched filename
  pattern, and network indicators.

  > Figure 4.37 - Analyst Recommendations

  Image description: Screenshot showing recommended analyst actions generated by the AI Sandbox report.

  > Figure 4.38 - Generated PDF Report Preview

  Image description: Screenshot showing the generated five-page PDF malware analysis report.

  ## 4.10 Validation Scenarios

  Three validation scenarios were used to evaluate SOCaaS. The primary validation scenario was the malware and AI Sandbox case study,
  because it demonstrates the added value of the platform beyond basic detection and notification. Two additional scenarios, Nmap port
  scan detection and C2 beacon detection, were used to validate reconnaissance and command-and-control detection. Their detailed
  screenshots, commands, and evidence are provided in appendices to keep the main chapter focused.

  ### 4.10.1 Malware and AI Sandbox Validation

  The malware validation scenario tested whether SOCaaS could support the investigation of a suspicious file. The controlled Python
  exfiltration sample was submitted to the AI Sandbox. The sandbox performed analysis, extracted indicators, reconstructed behavior,
  generated a risk verdict, and produced a five-page PDF report.

  The validation was successful because the sandbox recovered the same intended behavior as the original script. It identified
  recursive file searching, filename matching for password, file reading, TCP exfiltration, and the destination 192.168.122.1:4444. The
  TheHive investigation workflow was enriched with structured analysis output, allowing the analyst to understand the malware behavior
  without manually reversing the sample from the beginning.

  This validates the AI Sandbox as a practical SOCaaS capability for first-level malware triage. It reduces analyst workload and
  shortens the time needed to understand suspicious file behavior.

  ### 4.10.2 Nmap Port Scan Validation

  The Nmap port scan scenario validated reconnaissance detection. A controlled scan was executed against a monitored endpoint, and
  Wazuh generated alerts using the custom port scan and UFW-related detection rules. The Pipeline Gateway received the alerts,
  extracted observables such as source IP, destination IP, and ports, and reduced repeated alerts through deduplication.

  Shuffle then processed the normalized alert, sent analyst notifications, and created a case in TheHive. This scenario confirms that
  SOCaaS can detect and automate response to network reconnaissance activity. The detailed Nmap scenario, screenshots, and evidence are
  provided in Appendix A.

  ### 4.10.3 C2 Beacon Validation

  The C2 beacon scenario validated command-and-control detection. The test involved suspicious outbound communication from a monitored
  endpoint toward a controlled listener. Wazuh detected the suspicious communication, and the Pipeline Gateway extracted relevant IP,
  port, domain, or process context where available.

  The alert was enriched, processed by Shuffle, and supported by AI-generated response recommendations. These recommendations guided
  analyst actions such as host containment, network blocking, process investigation, and related-event hunting. The detailed C2
  scenario, screenshots, and evidence are provided in Appendix B.

  ## 4.11 Evaluation of Results

  The SOCaaS implementation was evaluated according to detection capability, alert forwarding, enrichment, automation, notification,
  case creation, AI assistance, and malware analysis support. The results show that SOCaaS successfully connects endpoint monitoring to
  automated investigation workflows.

  ┌──────────────────────────┬────────────┬────────────────────────────────────────────────┐
  │ Evaluation Point         │ Result     │ Evidence                                       │
  ├──────────────────────────┼────────────┼────────────────────────────────────────────────┤
  │ Wazuh detection          │ Successful │ Alerts generated                               │
  │ Pipeline forwarding      │ Successful │ /hooks/wazuh received alerts                   │
  │ Deduplication            │ Successful │ Repeated alerts reduced                        │
  │ VirusTotal enrichment    │ Successful │ Observable enrichment                          │
  │ Shuffle workflow         │ Successful │ Workflow completed                             │
  │ Telegram notification    │ Successful │ Analyst received alert                         │
  │ Email notification       │ Successful │ Analyst received email                         │
  │ TheHive case creation    │ Successful │ Case created                                   │
  │ AI recommendations       │ Successful │ Actions generated                              │
  │ AI Sandbox report        │ Successful │ 5-page PDF report generated                    │
  │ Sandbox logic extraction │ Successful │ Recovered logic matched original behavior      │
  │ Analyst time reduction   │ Positive   │ Report summarizes reverse engineering findings │
  └──────────────────────────┴────────────┴────────────────────────────────────────────────┘

  The results demonstrate that SOCaaS performs more than simple alert collection. Wazuh detects suspicious behavior, the Pipeline
  Gateway normalizes and enriches alerts, Shuffle automates triage, and TheHive stores cases for investigation. The AI recommendation
  node improves the analyst’s starting point by providing structured response guidance.

  The AI Sandbox produced the strongest validation result. The generated report reconstructed the behavior of the controlled malware
  sample and extracted relevant IOCs. This reduces the time required for first-level malware analysis from manual reverse engineering
  to automated triage and reporting. For SMEs, this is a significant improvement because it provides malware understanding without
  requiring a full-time malware analyst.

  Where screenshots support timing measurements, the platform can also be evaluated using operational metrics such as Mean Time to
  Detect and Mean Time to Respond. Based on available evidence, MTTD can be reported as less than or equal to one minute if alert
  timestamps confirm this result. MTTR can be discussed around fifteen minutes if supported by Shuffle workflow execution and analyst
  action evidence.

  ## 4.12 Limitations and Security Considerations

  Although the SOCaaS implementation successfully validates the proposed platform, several limitations and security considerations
  remain.

  First, the Kubernetes cluster uses a single control-plane node. This is sufficient for the laboratory implementation, but it does not
  provide control-plane high availability. In production, multiple control-plane nodes should be used to improve resilience.

  Second, AI-generated recommendations must be reviewed by analysts. The AI component supports triage but does not replace
  deterministic detection, enrichment, case evidence, or human decision-making. Analysts remain responsible for confirming the incident
  scope and approving containment actions.

  Third, the AI Sandbox must remain isolated. Malware samples should be analyzed only inside temporary isolated VMs, and infected VMs
  must not be reused. The implemented lifecycle, where the VM is destroyed after analysis and the temporary disk is deleted, reduces
  contamination risk.

  Fourth, malware sample acquisition must be controlled. Only authorized samples should be submitted to the sandbox, and reports should
  avoid exposing dangerous source code or reusable malware-building instructions.

  Fifth, private IP addresses such as those in the 192.168.122.0/24 laboratory network cannot be meaningfully scored by public
  reputation services such as VirusTotal. Enrichment results must therefore be interpreted according to the type of observable.

  Finally, production deployment should strengthen transport security, secrets management, access control, and persistence. TLS should
  be enforced for exposed services, secrets should be managed using a dedicated secrets management solution, and deduplication state
  should be made persistent if required by operational needs. The AI Sandbox report should support expert analysis, not replace it.

  ## 4.13 Conclusion

  This chapter presented the implementation and validation of the SOCaaS platform. The platform was deployed as an open-source, cloud-
  native SOC on Kubernetes using one control-plane node and two worker nodes. Wazuh provided endpoint detection, the Pipeline Gateway
  performed normalization, enrichment, and deduplication, Shuffle SOAR automated the response workflow, and TheHive provided case
  management.

  The validation scenarios demonstrated that SOCaaS can detect suspicious activity, process alerts, notify analysts, create cases, and
  support investigation workflows. The Nmap and C2 scenarios validated reconnaissance and command-and-control detection, while the
  malware scenario validated the AI Sandbox as a major added value.

  The AI Sandbox is the most important enhancement presented in this chapter. SOCaaS does not only detect and notify; it accelerates
  investigation by producing an AI-generated malware analysis report containing reconstructed logic, IOCs, MITRE ATT&CK mapping, a risk
  verdict, and recommended analyst actions. The controlled password-file exfiltration sample showed that the sandbox could recover the
  same behavior as the original script and produce a five-page report suitable for analyst triage.

  The detailed supporting evidence for the additional validation scenarios and sandbox report is provided in the appendices:

  - Appendix A: Nmap Port Scan Detection and Response
  - Appendix B: C2 Beacon Detection and Response
  - Appendix C: AI Sandbox Generated Malware Analysis Report
