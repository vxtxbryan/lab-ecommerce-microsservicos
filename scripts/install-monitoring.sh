#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi
helm upgrade --install monitoring kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts --version 93.11.0 \
  --namespace monitoring --create-namespace -f helm/platform/monitoring.yaml \
  --wait --timeout 15m
helm upgrade --install ecommerce-observability helm/observability \
  --namespace monitoring --wait
