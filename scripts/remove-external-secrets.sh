#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
current=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
if [[ "$current" != "$endpoint" ]]; then
  echo "Selecione no kubeconfig o cluster deste state Terraform." >&2
  exit 1
fi

if kubectl get applications -n argocd >/dev/null 2>&1; then
  echo "Remova primeiro o GitOps com scripts/remove-gitops.sh para excluir SecretStores." >&2
  exit 1
fi

helm uninstall external-secrets -n external-secrets --ignore-not-found --wait --timeout 10m
kubectl delete namespace external-secrets --ignore-not-found --wait=true --timeout=5m
