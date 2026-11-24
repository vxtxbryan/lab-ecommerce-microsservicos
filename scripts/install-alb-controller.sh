#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tf=(terraform -chdir=infra/terraform)
endpoint=$("${tf[@]}" output -raw cluster_endpoint)
if [[ "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$endpoint" ]]; then
  echo "Selecione o cluster deste state no kubeconfig." >&2
  exit 1
fi
chart=(aws-load-balancer-controller --repo https://aws.github.io/eks-charts --version 3.6.3)
# Helm só instala CRDs automaticamente no primeiro install.
helm show crds "${chart[@]}" | kubectl apply --server-side -f -
kubectl wait --for=condition=Established --timeout=2m \
  crd/ingressclassparams.elbv2.k8s.aws crd/targetgroupbindings.elbv2.k8s.aws
kubectl api-resources --cached=false >/dev/null
"${tf[@]}" output -json load_balancer_settings | \
  helm upgrade --install aws-load-balancer-controller "${chart[@]}" -n kube-system \
    --skip-crds -f helm/platform/aws-load-balancer-controller.yaml -f - --wait
