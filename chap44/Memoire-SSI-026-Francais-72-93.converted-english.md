# Chapter 4 - Implementation and Validation Testing

> **Conversion note:** this Markdown document reproduces the content of the provided PDF in English. Figures, screenshots, visual tables, and diagrams have been replaced with concise textual descriptions so that the document can be used as a reference model for writing a master's thesis in cybersecurity.

## 4.1 Introduction

This chapter presents the practical implementation of the Security Operations Center (SOC), covering both the technical deployment and the validation tests conducted to assess its effectiveness. It demonstrates how the proposed architecture meets key requirements for threat detection and rapid incident response through SOAR-based automation. The implementation includes the integration of core technologies such as SIEM and SOAR platforms, as well as the execution of attack simulations aligned with MITRE ATT&CK scenarios, with AI assistance for enhanced detection and response capabilities. The results of these tests are analyzed to evaluate the performance of the SOC in real-world conditions, providing insights into its operational effectiveness and areas for improvement, along with ai-sandbox analysis for the catshed malware samples to improve and fasten the investigation process.

## 4.2 Overview of the Kubernetes Cluster

The SOCaaS platform was deployed on a Kubernetes cluster composed of one Control Plane node and two Worker nodes. This architecture was selected to match the available lab resources while still providing a realistic cloud-native environment for deploying and managing SOC components.

The design focuses on workload separation, centralized orchestration, and operational scalability. The Control Plane node manages the cluster state and scheduling, while the Worker nodes execute the security services according to their functional role.

1. **Control Plane node: 1 machine**
   - **Node:** `k8s-master`
   - **Role:** management of the Kubernetes cluster, including orchestration, scheduling, API access, and cluster state control.
   - **Responsibility:** runs the main Kubernetes control-plane components such as the API server, scheduler, controller manager, and etcd.

2. **Worker nodes: 2 machines**
   - **Node:** `k8s-worker1`
     - **Role:** execution of SIEM workloads.
     - **Hosted services:** Wazuh Manager, Wazuh Indexer, Wazuh Dashboard, and related monitoring components.
   - **Node:** `k8s-worker2`
     - **Role:** execution of SOAR, case management, and automation workloads.
     - **Hosted services:** Shuffle, Pipeline Gateway, Redis, OpenSearch, TheHive, Cassandra, MinIO, and Elasticsearch.

3. **External access and service exposure**
   - The host machine provides external access to the Kubernetes services through NodePort services and HAProxy.
   - HAProxy is used to simplify access to exposed services such as the Kubernetes API, Wazuh, Shuffle, TheHive, and the pipeline gateway from the host network.

This architecture provides a clear separation between orchestration and operational workloads. It also allows the SOCaaS services to be distributed according to their purpose: Wazuh for detection on one Worker node, and Shuffle/TheHive for automation and incident response on the second Worker node. this architecture remains scalable because additional Worker nodes or redundant Control Plane nodes can be added in future production deployments.

> **Image description - Figure 4.1: SOCaaS Kubernetes Cluster Architecture**  
> The diagram illustrates the SOCaaS Kubernetes architecture. The host machine runs KVM/QEMU and connects all virtual machines through the `virbr0` network. At the center of the diagram, one Control Plane node named `k8s-master` manages the cluster through the Kubernetes API server, scheduler, controller manager, and etcd. Two Worker nodes are connected to it: `k8s-worker1`, dedicated to SIEM services such as Wazuh Manager, Wazuh Indexer, and Wazuh Dashboard; and `k8s-worker2`, dedicated to SOAR and incident response services such as Shuffle, Pipeline Gateway, TheHive, Cassandra, MinIO, Redis, and OpenSearch. HAProxy and NodePort services expose the platform interfaces to the host network. The diagram also shows victim endpoints connected to the same lab network and sending security events toward the SOCaaS detection pipeline.

### Table 4.1 - Cluster Components

| Name | Role | Operating System | Deployed Tools |
|---|---|---|---|
| `k8s-master` | Control Plane | Ubuntu Server 22.04 | kube-apiserver, etcd, kube-scheduler, kube-controller-manager, Calico |
| `k8s-worker1` | Worker | Ubuntu Server 22.04 | kubelet, kube-proxy, containerd, Wazuh Manager, Wazuh Indexer, Wazuh Dashboard |
| `k8s-worker2` | Worker | Ubuntu Server 22.04 | kubelet, kube-proxy, containerd, Shuffle, Pipeline Gateway, Redis, OpenSearch, TheHive, Cassandra, MinIO, Elasticsearch |

## 4.3 Deployment of the Kubernetes Cluster

The deployment of the Kubernetes cluster was performed using `kubeadm`, with `containerd` as the container runtime and Calico as the Container Network Interface. The deployment process was adapted to the SOCaaS lab architecture, which consists of one Control Plane node and two Worker nodes.

1. Installation of the **containerd** container runtime on all Kubernetes nodes.

> **Image description - Figure 4.2: Containerd Installation**  
> The screenshot shows a Linux terminal executing the command `containerd --version`. The output confirms that containerd is installed on the Kubernetes node and displays the installed version. This validates that the container runtime required by Kubernetes is available before initializing the cluster.

2. Installation of **kubeadm**, **kubelet**, and **kubectl** on all Kubernetes nodes.

> **Image description - Figure 4.3: Kubernetes Packages Installation**  
> The screenshot shows the Kubernetes packages installed on the node. It also shows the command `sudo apt-mark hold kubelet kubeadm kubectl`, which prevents unintended automatic upgrades. This step ensures version stability across the cluster during the SOCaaS deployment.

3. Initialization of the single Control Plane node using **kubeadm**.

> **Image description - Figure 4.4: Control Plane Initialization**  
> The screenshot shows the output of the `kubeadm init` command executed on `k8s-master`. The highlighted part confirms that the Kubernetes Control Plane was successfully initialized. The output also displays the commands required to configure `kubectl`, deploy the pod network, and join Worker nodes to the cluster.

4. Deployment of the **Calico CNI** plugin to enable pod networking inside the cluster.

> **Image description - Figure 4.5: Calico Network Deployment**  
> The screenshot shows the deployment of Calico network components in the `kube-system` namespace. The Calico pods appear in the `Running` state, confirming that pod-to-pod communication is enabled across the cluster.

5. Joining the two Worker nodes to the cluster using the `kubeadm join` command.

> **Image description - Figure 4.6: Joining Worker Nodes**  
> The screenshot shows the `kubeadm join` command executed from a Worker node. The highlighted message confirms that the node has successfully joined the cluster. This step was repeated for both `k8s-worker1` and `k8s-worker2`.

6. Verification of the Kubernetes cluster status.

> **Image description - Figure 4.7: Kubernetes Cluster Status**  
> The screenshot shows the output of `kubectl get nodes`, where `k8s-master`, `k8s-worker1`, and `k8s-worker2` appear in the `Ready` state. It also shows the output of `kubectl get pods -A -o wide`, where system components such as CoreDNS, Calico, kube-proxy, and Kubernetes control-plane pods are running correctly.

7. Deployment of SOCaaS services using Helm manifests and Kubernetes resources.

> **Image description - Figure 4.8: SOCaaS Workloads Running on Kubernetes**  
> The screenshot shows the SOCaaS namespaces and pods running in the cluster. The `socaas-siem` namespace contains Wazuh components on `k8s-worker1`, while the `socaas-soar` and `socaas-thehive` namespaces contain Shuffle, Pipeline Gateway, TheHive, and their supporting services on `k8s-worker2`. This confirms that the detection, automation, and case management components are successfully deployed.

At this stage, the Kubernetes cluster is operational and ready to host the SOCaaS detection and response stack. The single Control Plane node provides centralized orchestration, while the two Worker nodes distribute the operational SOC workloads according to their function.

## 4.4 Deployment of the Security Tools

After preparing the Kubernetes cluster, the SOCaaS security components were deployed as containerized services. The deployment relies on Kubernetes manifests and Helm templates that define the required resources for each component, including **Deployments**, **StatefulSets**, **Services**, **ConfigMaps**, **Secrets**, **PersistentVolumes**, and **PersistentVolumeClaims**.

In the SOCaaS architecture, the deployment is organized according to functional separation. The SIEM layer is deployed in the `socaas-siem` namespace on `k8s-worker1`, while the SOAR, pipeline, and incident response components are deployed on `k8s-worker2` through the `socaas-soar` and `socaas-thehive` namespaces. This separation improves readability, resource organization, and operational control.

Unlike a high-availability Kubernetes Control Plane architecture, this lab uses a single Control Plane node named `k8s-master`. Therefore, the objective of this deployment is not Control Plane redundancy, but rather a realistic SOCaaS environment with clear workload separation, persistent storage, exposed services, and automated detection and response capabilities.

### 4.4.1 Deployment of Wazuh SIEM

Wazuh was deployed as the SIEM layer of the SOCaaS platform. It is responsible for collecting endpoint events, correlating alerts, applying detection rules, and forwarding security events to the automation pipeline.

The Wazuh components were deployed in the `socaas-siem` namespace and assigned to `k8s-worker1`, which is dedicated to SIEM workloads.

The deployed Wazuh components include:

- **Wazuh Manager:** receives logs from agents, applies rules, and generates alerts.
- **Wazuh Indexer:** stores and indexes security alerts.
- **Wazuh Dashboard:** provides the web interface for alert visualization and monitoring.
- **Wazuh Alert Forwarder:** sidecar component that reads `alerts.json` and forwards alerts to the Pipeline Gateway.

1. The SOCaaS repository containing the Wazuh Kubernetes manifests and Helm templates is prepared.

> **Image description - Figure 4.9: Preparing Wazuh Deployment Files**  
> The screenshot shows the SOCaaS project directory containing the Kubernetes manifests or Helm templates used to deploy Wazuh. The files include the resources required for the Wazuh Manager, Indexer, Dashboard, services, secrets, and persistent storage.

2. The Wazuh resources are deployed in the `socaas-siem` namespace.

> **Image description - Figure 4.10: Applying Wazuh Resources**  
> The screenshot shows the execution of the deployment command used to apply the Wazuh resources. The output confirms the creation of Wazuh services, deployments, statefulsets, secrets, configmaps, and persistent volume claims in the `socaas-siem` namespace.

3. The Wazuh pods are verified on `k8s-worker1`.

> **Image description - Figure 4.11: Wazuh Pods on k8s-worker1**  
> The screenshot shows the output of `kubectl get pods -n socaas-siem -o wide`. The Wazuh Manager, Indexer, Dashboard, and related components appear in the `Running` state. The `NODE` column confirms that the SIEM workloads are running on `k8s-worker1`.

4. Access to the Wazuh Dashboard is validated.

> **Image description - Figure 4.12: Wazuh Dashboard**  
> The screenshot shows the Wazuh web interface accessed through the exposed NodePort service. The dashboard displays security monitoring modules, alert visualization, file integrity monitoring, vulnerability detection, and endpoint monitoring features.

### 4.4.2 Deployment of the Pipeline Gateway

The Pipeline Gateway is a central component in the SOCaaS detection flow. It receives Wazuh alerts, extracts observables, enriches them, removes duplicates, and forwards the normalized alert to the SOAR workflow and TheHive.

The Pipeline Gateway is deployed in the `socaas-soar` namespace on `k8s-worker2`.

Its main functions are:

- Receive Wazuh alerts through `/hooks/wazuh`.
- Validate incoming requests using a shared webhook secret.
- Extract observables such as IP addresses, domains, and hashes.
- Enrich observables using VirusTotal.
- Deduplicate repeated alerts using a 300-second TTL cache.
- Forward valid alerts to Shuffle.
- Create alerts or context in TheHive.

1. The Pipeline Gateway deployment is applied as part of the SOCaaS SOAR resources.

> **Image description - Figure 4.13: Pipeline Gateway Deployment**  
> The screenshot shows the Kubernetes resources created for the Pipeline Gateway in the `socaas-soar` namespace. The deployment, service, and configuration are visible, confirming that the gateway is available inside the cluster.

2. The Pipeline Gateway service is exposed through NodePort.

> **Image description - Figure 4.14: Pipeline Gateway Service**  
> The screenshot shows the Pipeline Gateway service exposed on port `30001`. This service allows Wazuh alerts and simulated webhook events to reach the SOCaaS pipeline from the host network.

3. The health endpoint is validated.

> **Image description - Figure 4.15: Pipeline Gateway Health Check**  
> The screenshot shows a request to the `/healthz` endpoint of the Pipeline Gateway. The response confirms that the gateway is running and ready to receive Wazuh alerts.

### 4.4.3 Deployment of Shuffle SOAR

Shuffle was deployed as the SOAR layer of SOCaaS. It automates the alert triage process by receiving alerts from the Pipeline Gateway, enriching them, generating recommended actions, notifying analysts, and creating TheHive cases.

Shuffle is deployed in the `socaas-soar` namespace on `k8s-worker2`.

The deployed Shuffle components include:

- **Shuffle Frontend:** web interface used to design and monitor workflows.
- **Shuffle Backend:** API and workflow engine.
- **Shuffle Orborus:** worker execution engine.
- **Shuffle OpenSearch:** storage backend for Shuffle data.
- **Redis:** cache and workflow queue component.
- **Pipeline Gateway:** alert ingestion and routing component.

1. The Shuffle resources are deployed in the `socaas-soar` namespace.

> **Image description - Figure 4.16: Applying Shuffle Resources**  
> The screenshot shows the deployment of Shuffle resources in Kubernetes. The output confirms the creation of services, deployments, persistent volumes, persistent volume claims, Redis, OpenSearch, frontend, backend, and Orborus components.

2. The Shuffle pods are verified on `k8s-worker2`.

> **Image description - Figure 4.17: Shuffle Pods on k8s-worker2**  
> The screenshot shows the output of `kubectl get pods -n socaas-soar -o wide`. Shuffle components such as the frontend, backend, Orborus, OpenSearch, Redis, and Pipeline Gateway appear in the `Running` state. The `NODE` column confirms that the SOAR workloads are running on `k8s-worker2`.

3. Access to the Shuffle interface is validated.

> **Image description - Figure 4.18: Shuffle Dashboard**  
> The screenshot shows the Shuffle web interface. The platform displays automation-related menus such as workflows, apps, executions, files, cloud sync, and administration. This confirms that the SOAR platform is accessible and operational.

### 4.4.4 Deployment of TheHive Case Management Platform

TheHive was deployed as the incident response and case management layer of SOCaaS. It stores alerts, cases, observables, investigation details, and analyst tracking information.

TheHive is deployed in the `socaas-thehive` namespace on `k8s-worker2`.

The deployed TheHive components include:

- **TheHive:** case management web application and API.
- **Cassandra:** main database backend.
- **Elasticsearch:** search and indexing backend.
- **MinIO:** object storage for files and attachments.

1. The TheHive Kubernetes resources are prepared.

> **Image description - Figure 4.19: Preparing TheHive Deployment Files**  
> The screenshot shows the Kubernetes manifest or Helm template files used to deploy TheHive and its dependencies. The files include resources for TheHive, Cassandra, Elasticsearch, MinIO, services, statefulsets, and persistent storage.

2. The TheHive resources are deployed in the `socaas-thehive` namespace.

> **Image description - Figure 4.20: Applying TheHive Resources**  
> The screenshot shows the execution of the deployment command for TheHive. The output confirms the creation of TheHive, Cassandra, Elasticsearch, MinIO, services, statefulsets, deployments, and persistent volume claims.

3. The TheHive pods are verified on `k8s-worker2`.

> **Image description - Figure 4.21: TheHive Pods on k8s-worker2**  
> The screenshot shows the output of `kubectl get pods -n socaas-thehive -o wide`. TheHive, Cassandra, Elasticsearch, and MinIO pods appear in the `Running` state, confirming that the incident response platform is operational.

4. Access to TheHive is validated.

> **Image description - Figure 4.22: TheHive Dashboard**  
> The screenshot shows TheHive accessed through the exposed NodePort service. The interface displays alerts, cases, observables, and incident tracking information, confirming that the case management platform is accessible.

## 4.5 Implementation of the SOCaaS Helm Chart

To make the platform reusable and easier to deploy, the SOCaaS Kubernetes manifests were consolidated into a Helm chart. The Helm chart packages the SIEM, SOAR, Pipeline Gateway, and TheHive resources into a structured deployment model.

The chart is named `socaas` and is located inside the SOCaaS project directory. It is designed to support repeatable deployment for future SOCaaS environments.

The Helm chart organizes the platform into the following logical groups:

- `socaas-siem`: Wazuh Manager, Indexer, Dashboard, and alert forwarder.
- `socaas-soar`: Shuffle, Pipeline Gateway, Redis, and OpenSearch.
- `socaas-thehive`: TheHive, Cassandra, MinIO, and Elasticsearch.
- `socaas-system`: Helm release and platform-level resources.

1. The Helm chart is created.

> **Image description - Figure 4.23: Creating the SOCaaS Helm Chart**  
> The screenshot shows the command used to create or prepare the `socaas` Helm chart. The generated chart directory contains the standard Helm structure, including `Chart.yaml`, `values.yaml`, `charts`, and `templates`.

2. The chart structure is verified.

> **Image description - Figure 4.24: SOCaaS Helm Chart Structure**  
> The screenshot shows the contents of the SOCaaS Helm chart. The `templates` directory contains the Kubernetes resources used to deploy Wazuh, Shuffle, the Pipeline Gateway, and TheHive.

3. The manifests are organized by SOCaaS component.

> **Image description - Figure 4.25: Organized SOCaaS Helm Templates**  
> The screenshot shows the Helm chart template structure organized by component. The folders group resources for `wazuh`, `shuffle`, `pipeline-gateway`, and `thehive`, including deployments, statefulsets, services, secrets, configmaps, RBAC resources, and persistent storage definitions.

This packaging approach makes the SOCaaS platform easier to reproduce, update, and adapt for future client environments.

## 4.6 Attack Simulation: Malware Case Study

A controlled malware attack simulation was conducted to validate the SOCaaS detection and response pipeline. The objective was to verify that the platform can detect suspicious activity on an endpoint, enrich the alert, notify analysts, generate recommendations, create a case in TheHive, and support automated response actions.

The simulation focuses on a Windows endpoint monitored by the Wazuh agent. The malicious behavior is based on a malware dropper scenario in which an executable is downloaded and executed on the victim machine. The dropper places suspicious files in the user profile, creates persistence, and attempts to communicate with the attacker through a non-standard port.

The attack chain is mapped to MITRE ATT&CK techniques such as:

- **T1204 - User Execution**
- **T1547.001 - Registry Run Keys / Startup Folder**
- **T1571 - Non-Standard Port**
- **T1564.001 - Hidden Files**
- **T1041 - Exfiltration Over C2 Channel**

### 4.6.1 Initial Access and Execution

The attacker delivers a malicious executable to the Windows victim machine. The file is disguised as a legitimate document or installer in order to encourage the user to execute it.

Once executed, the dropper performs several actions:

- Downloads or drops suspicious files into the user profile.
- Places payloads inside the `AppData` directory.
- Creates persistence through a registry Run key.
- Starts a process that attempts to communicate with the attacker.
- Generates endpoint activity that can be detected by Wazuh.

> **Image description - Figure 4.26: Malicious File Download**  
> The screenshot shows the victim downloading a suspicious executable from a controlled simulation server. The browser or download page displays the file being retrieved by the Windows endpoint.

> **Image description - Figure 4.27: Malicious File on the Victim Machine**  
> The screenshot shows Windows File Explorer with the downloaded executable visible in the victim's download directory. This confirms that the file has reached the endpoint before execution.

### 4.6.2 Malware Dropper Behavior

After execution, the malware dropper places suspicious files inside the victim's user directory. In the SOCaaS lab, this behavior is used to trigger file integrity monitoring and malware-related detections.

The main observed behaviors are:

- Creation of executable files under `AppData`.
- Creation of persistence through the Windows registry.
- Execution of a suspicious process.
- Attempted communication through port `4444`.
- Generation of file integrity and process-related events.

> **Image description - Figure 4.28: Suspicious Files in AppData**  
> The screenshot shows Windows File Explorer opened inside the `AppData` directory. Suspicious executable files are visible, demonstrating that the dropper has placed payloads in a user-level application directory.

### 4.6.3 Detection by Wazuh

Wazuh detects the malicious behavior through endpoint monitoring, file integrity monitoring, registry monitoring, and custom rules.

The main detections include:

- New executable file added to the system.
- Suspicious file path under `AppData`.
- Registry modification used for persistence.
- Process execution related to the dropped payload.
- Connection attempt to a non-standard port.

> **Image description - Figure 4.29: Detection of a New Executable File**  
> The screenshot shows Wazuh alerts related to file integrity monitoring. The alerts indicate that a new executable file has been added to the monitored endpoint.

> **Image description - Figure 4.30: Detection of Suspicious Process or Port**  
> The screenshot shows the detailed JSON view of a Wazuh alert. Important fields such as the agent name, process path, process identifier, destination port, and MITRE ATT&CK mapping are highlighted.

### 4.6.4 Alert Forwarding Through the Pipeline Gateway

After Wazuh generates the alert, the Wazuh Alert Forwarder reads the alert from `alerts.json` and forwards it to the Pipeline Gateway through the `/hooks/wazuh` endpoint.

The Pipeline Gateway performs the following operations:

1. Validates the request using the shared webhook secret.
2. Extracts observables such as IP addresses, domains, and hashes.
3. Performs VirusTotal enrichment when possible.
4. Applies deduplication using a 300-second TTL cache.
5. Forwards the normalized alert to the Shuffle webhook.
6. Creates alert context for TheHive.

This design prevents alert flooding. For example, a scan or repeated event sequence may generate many raw Wazuh alerts, but the deduplication logic forwards only the first relevant alert during the TTL window.

> **Image description - Figure 4.31: Alert Forwarding to Pipeline Gateway**  
> The screenshot shows the Pipeline Gateway receiving a Wazuh alert through the `/hooks/wazuh` endpoint. The output confirms that the alert was accepted, normalized, and forwarded to the next stage.

### 4.6.5 Automated Response Workflow in Shuffle

Shuffle receives the normalized alert from the Pipeline Gateway and launches the SOCaaS Wazuh Alert Triage workflow.

The workflow contains the following actions:

1. **Webhook_1:** receives the alert from the Pipeline Gateway.
2. **Normalize_SOC_Alert:** parses the raw alert and extracts useful fields such as rule ID, agent name, source IP, destination IP, observables, severity, Telegram message, e-mail body, and TheHive case payload.
3. **Virustotal_v3:** enriches the observable using VirusTotal.
4. **Generate_AI_Recommended_Actions:** generates recommended analyst actions based on the alert context.
5. **Build_Context_TheHive_Email_Body:** builds the final context for TheHive and notification messages.
6. **Send_Telegram_Notification:** sends a formatted alert to Telegram.
7. **Send_Email_Notification:** sends an e-mail notification to the analyst.
8. **Create_TheHive_Case:** creates a structured case in TheHive.
9. **Final_Response:** returns the workflow execution summary.

> **Image description - Figure 4.32: SOCaaS Shuffle Workflow**  
> The screenshot shows the complete Shuffle workflow. The automation chain starts with the webhook trigger, followed by alert normalization, VirusTotal enrichment, AI recommended actions, context building, Telegram notification, e-mail notification, TheHive case creation, and final response.

> **Image description - Figure 4.33: VirusTotal Enrichment Result**  
> The screenshot shows the output of the VirusTotal action in Shuffle. The JSON result includes reputation or analysis statistics for the extracted observable, such as malicious, suspicious, harmless, and undetected counts.

### 4.6.6 AI Sandbox Malware Analysis

For malware-related alerts, the suspicious file can be submitted to the SOCaaS AI Sandbox. This component strengthens the response process by analyzing suspicious files in an isolated environment before an analyst makes a final decision.

The AI Sandbox performs the following steps:

1. Receives the suspicious malware file from the alert context.
2. Creates a temporary isolated virtual machine.
3. Executes controlled static and dynamic analysis.
4. Performs reverse engineering to extract malware logic.
5. Produces reversed code or pseudocode when possible.
6. Generates a PDF report describing the malware behavior, indicators, and recommended actions.
7. Sends the analysis summary back to the SOC workflow or TheHive case.

> **Image description - Figure 4.34: AI Sandbox Malware Report**  
> The screenshot shows the AI Sandbox output report. The report contains the malware behavior summary, extracted indicators, reverse engineering findings, pseudocode or reversed logic, and analyst recommendations.

### 4.6.7 Case Creation and Analyst Notification

Once the alert is enriched and the context is built, the workflow creates a case in TheHive. The case includes the alert description, severity, affected endpoint, observables, enrichment results, and recommended response actions.

At the same time, the analyst receives notifications through Telegram and e-mail. These notifications provide a fast summary of the incident so that the SOC team can react quickly.

> **Image description - Figure 4.35: Case Creation in TheHive**  
> The screenshot shows TheHive displaying a case created from the SOCaaS workflow. The case contains information such as severity, title, description, observables, and investigation status.

> **Image description - Figure 4.36: Analyst Notification**  
> The screenshot shows a Telegram or e-mail notification generated by the SOCaaS workflow. The message includes the alert severity, affected agent, rule description, observables, VirusTotal result, and case reference.

### 4.6.8 Response and Containment

If the alert is confirmed to be malicious, the response process can perform containment actions. Depending on the scenario, these actions may include removing a malicious file, terminating a suspicious process, or blocking an indicator.

For process-based detection, the workflow extracts the suspicious process identifier and executes a response action to terminate it.

> **Image description - Figure 4.37: Suspicious Process Termination**  
> The screenshot shows a Shuffle response action that terminates the suspicious process using the process ID extracted from the Wazuh alert.

> **Image description - Figure 4.38: Response Action Result**  
> The screenshot shows the response action status as `SUCCESS`, confirming that the suspicious process was terminated or the malicious artifact was removed.

### 4.6.9 Command and Control Observation

If the backdoor is not contained, the attacker may establish a reverse shell or command-and-control session with the victim machine. This gives the attacker remote access and may allow further actions such as file manipulation, data exfiltration, or lateral movement.

> **Image description - Figure 4.39: Reverse Shell Observation**  
> The screenshot shows a controlled reverse shell session in the lab environment. The terminal demonstrates how the attacker could interact with the victim machine if the malicious process is not detected and contained.

### 4.6.10 Impact Demonstration

The final phase demonstrates the potential impact if the SOC does not detect or respond to the incident. In a real-world scenario, this could result in data theft, persistence, ransomware execution, or service disruption.

This impact phase is used only as a controlled demonstration to show why early detection and automated response are important.

> **Image description - Figure 4.40: Impact Demonstration**  
> The screenshot shows the potential consequence of a successful malware execution, such as file encryption, system compromise, or attacker-controlled activity on the victim machine.

## 4.7 Evaluation of Simulation Results

This section evaluates the effectiveness of the SOCaaS platform during the attack simulation. The evaluation focuses on detection speed, response speed, enrichment quality, case creation, and notification delivery.

### 4.7.1 Mean Time to Detect

The Mean Time to Detect measures the time between the malicious activity and the generation of an alert by Wazuh.

During the simulation, Wazuh detected the main suspicious activities in near real time, including:

- New executable file creation.
- Suspicious file location under `AppData`.
- Registry modification.
- Process execution.
- Connection to a non-standard port.

The average detection time was less than or equal to one minute.

> **Image description - Figure 4.41: Detection Time in Wazuh**  
> The screenshot shows Wazuh alerts with highlighted timestamps. These timestamps are used to compare the time of the malicious activity with the time of detection.

### 4.7.2 Mean Time to Respond

The Mean Time to Respond measures the time between alert detection and the completion of the automated response workflow.

The SOCaaS response process included:

- Alert forwarding through the Pipeline Gateway.
- Observable extraction.
- VirusTotal enrichment.
- AI recommended actions.
- Telegram notification.
- E-mail notification.
- TheHive case creation.
- Optional AI Sandbox malware analysis.
- Response or containment action.

The automated response workflow completed in approximately 15 minutes, depending on enrichment and analysis duration.

> **Image description - Figure 4.42: Response Time in Shuffle**  
> The screenshot shows the Shuffle workflow execution summary. The start and finish timestamps are highlighted to estimate the total response time.

### 4.7.3 Evaluation Summary

The simulation confirms that SOCaaS can detect, enrich, and respond to security incidents through an integrated open-source architecture.

| Evaluation Point | Result |
|---|---|
| Alert detection | Successful |
| Alert forwarding | Successful through Pipeline Gateway |
| Deduplication | Successful with 300-second TTL cache |
| Observable extraction | Successful |
| VirusTotal enrichment | Successful |
| AI recommendation | Successful |
| TheHive case creation | Successful |
| Telegram notification | Successful |
| E-mail notification | Successful |
| Response action | Successful in controlled scenarios |
| AI Sandbox report | Successful for malware-analysis scenarios |

The results demonstrate that the SOCaaS platform reduces manual analyst effort by automating the repetitive stages of alert triage, enrichment, notification, and case creation.

## 4.8 Conclusion

This chapter presented the practical deployment and validation of the SOCaaS platform. The implementation used Kubernetes to host the main SOC components, including Wazuh for detection, the Pipeline Gateway for alert normalization and routing, Shuffle for automation, TheHive for case management, and the AI Sandbox for malware analysis.

The deployment followed the real SOCaaS architecture: one Control Plane node, two Worker nodes, dedicated namespaces, persistent storage, and exposed services through NodePort and HAProxy. The SIEM workloads were assigned to `k8s-worker1`, while the SOAR, Pipeline Gateway, and case management workloads were assigned to `k8s-worker2`.

The attack simulation demonstrated that the platform can detect suspicious activity, enrich observables, generate recommended actions, notify analysts, create TheHive cases, and support automated response. The evaluation results show that SOCaaS provides a realistic, open-source, and automated SOC environment suitable for small and medium-sized organizations that need security monitoring and incident response without relying on expensive proprietary platforms.