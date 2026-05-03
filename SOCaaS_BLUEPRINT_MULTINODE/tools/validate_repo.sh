#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '[validate] shell syntax\n'
while IFS= read -r f; do
  bash -n "$f"
done < <(find "$ROOT/scripts" -type f -name '*.sh' | sort)

printf '[validate] yaml files without Helm templates\n'
mapfile -t yaml_files < <(find "$ROOT/manifests" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
yaml_files+=("$ROOT/charts/socaas/values.yaml" "$ROOT/charts/socaas/values-multinode.yaml" "$ROOT/charts/socaas/Chart.yaml")
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_stream(File.read(f)); puts "OK #{f}" }' "${yaml_files[@]}"

printf '[validate] static Helm path audit available: ruby tools/audit_helm_values_paths.rb\n'
printf '[validate] done\n'
