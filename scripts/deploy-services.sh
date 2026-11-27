#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Validate every release before contacting the cluster or modifying any workload.
tags=$(python3 - <<'PY'
import json, os, re
import yaml
services = ('products', 'users', 'payments', 'orders')
provided = os.getenv('IMAGE_TAG')
tags = {}
for service in services:
    with open(f'helm/values/{service}.yaml') as file:
        values = yaml.safe_load(file)
    tags[service] = provided or values.get('image', {}).get('tag')
if any(not isinstance(tag, str) or not re.fullmatch(r'[0-9a-f]{40}', tag) for tag in tags.values()):
    raise SystemExit('Defina IMAGE_TAG ou os SHAs completos em helm/values/*.yaml.')
print(json.dumps(tags))
PY
)
endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi
values=$(terraform -chdir=infra/terraform output -json service_helm_values)
monitor_args=()
if [[ "${MONITORING:-false}" == true ]]; then
  kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null
  monitor_args=(--set serviceMonitor.enabled=true)
fi
for service in products users payments orders; do
  config=$(python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$service" <<< "$values")
  tag=$(python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$service" <<< "$tags")
  helm upgrade --install "$service" helm/microservice --namespace default \
    -f "helm/values/$service.yaml" -f - --set-string "image.tag=$tag" \
    "${monitor_args[@]}" --wait --timeout 10m <<< "$config"
done
