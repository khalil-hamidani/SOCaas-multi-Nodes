# 21 - Audit Notes for Uploaded Materials

This file documents the correction pass applied while generating this multi-node blueprint.

## Current blueprint observations

The uploaded current blueprint is internally useful but describes a single-node or hybrid-local deployment. It explicitly locks `DEPLOYMENT_MODE=hybrid-local-single-node` and `K8S_TYPE=kubeadm-single-node`. That does not match a thesis architecture requiring one dedicated control-plane VM plus two worker VMs.

## Execution guide observations

The uploaded guide correctly points toward:

- Parrot host with KVM;
- three Ubuntu VMs;
- Kubernetes with kubeadm and containerd;
- Calico CNI;
- HAProxy on the host;
- Wazuh, Shuffle, TheHive;
- a separate Wazuh Agent laptop.

Common mistakes corrected here:

| Mistake class | Correction in this repo |
|---|---|
| `.Values.nodeSelector` vs `.Values.global.nodeSelector` mismatch | all scheduling paths use `.Values.scheduling.*` |
| labels not matching service selectors | every Service selector matches template pod labels |
| policies selecting labels that do not exist | network policies use actual `app.kubernetes.io/*` labels |
| master accepting workloads | control-plane taint is preserved and verified |
| local PVs not pinned | every local PV has nodeAffinity to worker1 or worker2 |
| impossible laptop resources | requests/limits are reduced in `values-multinode.yaml` |
| missing probes | readiness/liveness/startup probes are included where practical |
| missing secrets | credentials are rendered as Kubernetes Secrets |
| missing troubleshooting commands | scripts and docs include reset, logs, describe, and network checks |
| wrong service names | service names are fixed and referenced consistently |

## Validation included

Run:

```bash
bash tools/validate_repo.sh
ruby tools/audit_helm_values_paths.rb
```

These checks do not replace a real cluster deployment test, but they catch the common static errors: shell syntax, YAML parse issues in non-template manifests, and broken Helm values paths.
