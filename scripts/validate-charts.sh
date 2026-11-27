#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:?Informe o diretório de manifests renderizados}
mkdir -p "$output"
for service in products users orders payments; do
  helm lint helm/microservice -f "helm/values/$service.yaml" --set-string image.tag=0000000000000000000000000000000000000000
  helm template "$service" helm/microservice -f "helm/values/$service.yaml" \
    --set-string image.tag=0000000000000000000000000000000000000000 \
    --set serviceMonitor.enabled=true,autoscaling.enabled=true,podDisruptionBudget.enabled=true \
    --set-string serviceAccount.roleArn=arn:aws:iam::123456789012:role/validation \
    > "$output/$service.yaml"
done
helm template payments helm/microservice -f helm/values/payments.yaml \
  --set-string image.tag=0000000000000000000000000000000000000000 \
  --set 'secretEnv[0].name=API_KEY' \
  --set 'secretEnv[0].secretName=payments-api-credentials' \
  --set 'secretEnv[0].secretKey=API_KEY' > "$output/payments-secret-env.yaml"
python3 - "$output/payments-secret-env.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as stream:
    resources = list(yaml.safe_load_all(stream))
deployment = next(item for item in resources if item and item["kind"] == "Deployment")
env = deployment["spec"]["template"]["spec"]["containers"][0]["env"]
api_key = next(item for item in env if item["name"] == "API_KEY")
assert api_key["valueFrom"]["secretKeyRef"] == {
    "name": "payments-api-credentials", "key": "API_KEY", "optional": False
}
PY
helm lint helm/karpenter-capacity --set cluster=validation,instanceProfile=validation
helm template capacity helm/karpenter-capacity --set cluster=validation,instanceProfile=validation > "$output/capacity.yaml"
helm lint helm/observability
helm template ecommerce-observability helm/observability -n monitoring > "$output/observability.yaml"
