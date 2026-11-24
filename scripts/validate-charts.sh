#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:?Informe o diretório de manifests renderizados}
mkdir -p "$output"
for service in products users orders payments; do
  helm lint helm/microservice -f "helm/values/$service.yaml"
  helm template "$service" helm/microservice -f "helm/values/$service.yaml" \
    --set-string serviceAccount.roleArn=arn:aws:iam::123456789012:role/validation \
    > "$output/$service.yaml"
done
helm lint helm/karpenter-capacity --set cluster=validation,instanceProfile=validation
helm template capacity helm/karpenter-capacity --set cluster=validation,instanceProfile=validation > "$output/capacity.yaml"
