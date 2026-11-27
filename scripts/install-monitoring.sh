#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi
chart=(kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts --version 93.11.0)
# Helm installs CRDs before release resources, but its discovery cache may not
# recognize those CRDs in the same operation. Apply and wait for them first.
helm show crds "${chart[@]}" | kubectl apply --server-side -f -
while IFS= read -r crd; do
  kubectl wait --for=condition=Established --timeout=2m "$crd"
done < <(kubectl get crd -o name | grep '\.monitoring\.coreos\.com$')
kubectl api-resources --cached=false >/dev/null
helm upgrade --install monitoring "${chart[@]}" \
  --namespace monitoring --create-namespace -f helm/platform/monitoring.yaml \
  --wait --timeout 15m
helm upgrade --install ecommerce-observability helm/observability \
  --namespace monitoring --wait
