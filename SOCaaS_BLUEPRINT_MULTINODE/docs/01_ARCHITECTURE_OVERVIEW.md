# 01 - Architecture Overview

## Multi-node virtual architecture

```text
Separate monitored laptop
  Wazuh Agent
      |
      | TCP 1514/1515 through HAProxy on Parrot host
      v
Parrot host 192.168.122.1
  HAProxy
      | Kubernetes API -> k8s-master:6443
      | Wazuh -> k8s-worker1 NodePorts
      | Shuffle -> k8s-worker2 NodePort
      | TheHive -> k8s-worker2 NodePort
      v
KVM/libvirt VMs
  k8s-master  192.168.122.10  control-plane only
  k8s-worker1 192.168.122.11  Wazuh SIEM
  k8s-worker2 192.168.122.12  Shuffle + TheHive + dependencies
```

## Why this aligns better with a thesis

The old blueprint treated the main host as a single Kubernetes node or hybrid host/container deployment. That is useful for fitting into a laptop, but it does not show a real control-plane/worker separation. This blueprint demonstrates:

1. a dedicated control plane;
2. separate SIEM and SOAR/IR worker roles;
3. Kubernetes scheduling constraints;
4. local PV node affinity;
5. service exposure through a host load balancer;
6. Calico policies for east-west traffic control.

## SOC alert flow

```text
Wazuh Agent -> HAProxy -> Wazuh Manager -> alerts.json -> Wazuh alert forwarder sidecar
  -> socaas-pipeline-gateway in socaas-soar
  -> optional native Shuffle webhook
  -> TheHive API / analyst workflow
```

The pipeline gateway gives deterministic lab validation even before the Shuffle workflow is customized. For the final thesis demo, create a native Shuffle workflow and set `SOCAAS_NATIVE_SHUFFLE_WEBHOOK_URL` so the gateway forwards each Wazuh alert to Shuffle.
