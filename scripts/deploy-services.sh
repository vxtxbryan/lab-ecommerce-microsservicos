#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${IMAGE_TAG:-}" ]]; then
  if [[ ! -f helm/releases.yaml ]]; then
    echo "Defina IMAGE_TAG ou configure helm/releases.yaml." >&2
    exit 1
  fi
fi
values=$(terraform -chdir=infra/terraform output -json service_helm_values)
for service in products users payments orders; do
  config=$(python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$service" <<< "$values")
  if [[ -n "${IMAGE_TAG:-}" ]]; then
    tag_args=(--set-string "image.tag=$IMAGE_TAG")
  else
    release_tag=$(python3 -c 'import yaml,sys; print(yaml.safe_load(open(sys.argv[1]))[sys.argv[2]] or "")' helm/releases.yaml "$service")
    if [[ ! "$release_tag" =~ ^[0-9a-f]{40}$ ]]; then
      echo "helm/releases.yaml não tem SHA completo válido para $service." >&2
      exit 1
    fi
    tag_args=(--set-string "image.tag=$release_tag")
  fi
  helm upgrade --install "$service" helm/microservice --namespace default \
    -f "helm/values/$service.yaml" -f - "${tag_args[@]}" --wait <<< "$config"
done
