# 10 - Helm Deployment

Install Helm on the master:

```bash
bash scripts/10_install_helm.sh
```

Deploy the chart:

```bash
bash scripts/11_deploy_socaas.sh
```

Equivalent manual commands on the master:

```bash
cd ~/SOCaaS_BLUEPRINT_MULTINODE
sudo install -d -m 0755 -o "$(id -u)" -g "$(id -g)" /srv/socaas/generated/helm
helm lint charts/socaas -f charts/socaas/values-multinode.yaml
helm template socaas charts/socaas -f charts/socaas/values-multinode.yaml > /srv/socaas/generated/helm/socaas-rendered.yaml
helm upgrade --install socaas charts/socaas \
  -n socaas-system --create-namespace \
  -f charts/socaas/values-multinode.yaml \
  --timeout 20m --wait
```

The deployment script also copies the rendered manifest back to the host under `/srv/socaas/generated/helm/socaas-rendered.yaml`.

## Values-path discipline

The chart intentionally avoids mixing `.Values.nodeSelector` with `.Values.global.nodeSelector`. Scheduling values are under:

```yaml
scheduling:
  siemNodeSelector:
    node-role: siem
  soarNodeSelector:
    node-role: soar
```

Namespaces are under:

```yaml
namespaces:
  system: socaas-system
  siem: socaas-siem
  soar: socaas-soar
  ir: socaas-thehive
```

Run the static audit locally:

```bash
ruby tools/audit_helm_values_paths.rb
```
