#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi
helm uninstall ecommerce-observability -n monitoring --ignore-not-found --wait --timeout 10m
helm uninstall monitoring -n monitoring --ignore-not-found --wait --timeout 10m
kubectl delete namespace monitoring --ignore-not-found --wait=true --timeout=5m
