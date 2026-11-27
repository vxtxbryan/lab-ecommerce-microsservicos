#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

endpoint=$(terraform -chdir=infra/terraform output -raw cluster_endpoint)
current=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
if [[ "$current" != "$endpoint" ]]; then
  echo "Selecione no kubeconfig o cluster deste state Terraform." >&2
  exit 1
fi

version=$(kubectl version -o json | python3 -c 'import json,sys; v=json.load(sys.stdin)["serverVersion"]; print(v["major"].split(".")[0]+"."+v["minor"].rstrip("+"))')
if [[ "$version" != "1.37" ]]; then
  echo "External Secrets Operator 2.15.0 foi configurado para Kubernetes 1.37; cluster atual: $version. Atualize a versão fixada e valide a compatibilidade em conjunto." >&2
  exit 1
fi

role_arn=$(terraform -chdir=infra/terraform output -raw external_secrets_role_arn)
crds_url="https://raw.githubusercontent.com/external-secrets/external-secrets/helm-chart-2.15.0/deploy/crds/bundle.yaml"
kubectl apply --server-side -f "$crds_url"
while IFS= read -r crd; do
  kubectl wait --for=condition=Established --timeout=2m "$crd"
done < <(kubectl get crd -l external-secrets.io/component=controller -o name)
kubectl api-resources --cached=false >/dev/null

helm upgrade --install external-secrets external-secrets \
  --repo https://charts.external-secrets.io --version 2.15.0 \
  --namespace external-secrets --create-namespace \
  -f helm/platform/external-secrets.yaml \
  --set installCRDs=false \
  --set-string 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn'="$role_arn" \
  --wait --timeout 10m

kubectl rollout status deployment/external-secrets \
  -n external-secrets --timeout=10m
echo "External Secrets Operator instalado. O SecretStore será sincronizado pelo Argo CD."
