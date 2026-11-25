#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

values=$(terraform -chdir=infra/terraform output -json service_helm_values)
if [[ -z "${IMAGE_TAG:-}" ]]; then
  echo "Defina IMAGE_TAG com o SHA publicado no ECR." >&2
  exit 1
fi
tag_args=(--set-string "image.tag=$IMAGE_TAG")
for service in products users payments orders; do
  config=$(python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$service" <<< "$values")
  helm upgrade --install "$service" helm/microservice --namespace default \
    -f "helm/values/$service.yaml" -f - "${tag_args[@]}" --wait <<< "$config"
done
