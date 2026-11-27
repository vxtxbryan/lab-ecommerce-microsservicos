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
  # Delete leaf Applications while their AppProject still exists. The root
  # app's prune order is not deterministic, so deleting it first can remove
  # the project before Argo CD runs the leaf finalizers.
  for app in orders payments products users; do
    kubectl delete application "$app" -n argocd --ignore-not-found \
      --cascade=foreground --wait --timeout=10m
  done
  kubectl delete application ecommerce-root -n argocd --ignore-not-found \
    --cascade=foreground --wait --timeout=10m
fi
helm uninstall argocd -n argocd --ignore-not-found --wait --timeout=10m
echo "Aplicações GitOps e Argo CD removidos."
