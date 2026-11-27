#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
current=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
if [[ "$current" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi

helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version 10.19.1 \
  --namespace argocd --create-namespace \
  -f gitops/argocd/values.yaml --wait --timeout 15m

kubectl apply -f gitops/bootstrap/root-application.yaml
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/ecommerce-root -n argocd --timeout=5m
for service in products users payments orders; do
  kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
    "application/$service" -n argocd --timeout=15m
  kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
    "application/$service" -n argocd --timeout=15m
done
echo "Argo CD instalado; o app-of-apps está acompanhando a branch main."
