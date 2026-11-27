#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
current=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
if [[ "$current" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi

if kubectl get application ecommerce-root -n argocd >/dev/null 2>&1; then
  if kubectl get application orders -n argocd >/dev/null 2>&1; then
    kubectl patch application orders -n argocd --type=merge \
      -p '{"spec":{"syncPolicy":{"automated":null}}}'
    bash scripts/remove-alb-controller.sh
  fi
  kubectl delete application ecommerce-root -n argocd \
    --cascade=foreground --wait --timeout=15m
fi
helm uninstall argocd -n argocd --ignore-not-found --wait --timeout=10m
echo "Aplicações GitOps e Argo CD removidos."
