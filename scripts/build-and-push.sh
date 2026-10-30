#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="271251458777"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
PROJECT_NAME="ecommerce-microsservicos"

SERVICES=("products" "orders" "users" "payments")

push_with_retry() {
  local IMAGE=$1
  local MAX_TRIES=3
  local TRY=1

  while [ $TRY -le $MAX_TRIES ]; do
    echo "Tentativa $TRY de $MAX_TRIES..."
    if docker push "$IMAGE"; then
      return 0
    fi
    echo "Push falhou, tentando novamente em 5s..."
    sleep 5
    TRY=$((TRY + 1))
  done

  echo "Falha apos $MAX_TRIES tentativas para $IMAGE"
  return 1
}

echo "Fazendo login no ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

for SERVICE in "${SERVICES[@]}"; do
  echo ""
  echo "=== Processando $SERVICE ==="

  IMAGE_NAME="${PROJECT_NAME}-${SERVICE}"
  FULL_IMAGE="${ECR_REGISTRY}/${IMAGE_NAME}:latest"

  echo "Buildando imagem..."
  docker build -t "$IMAGE_NAME" "./services/${SERVICE}"

  echo "Aplicando tag para o ECR..."
  docker tag "${IMAGE_NAME}:latest" "$FULL_IMAGE"

  echo "Enviando para o ECR..."
  push_with_retry "$FULL_IMAGE"

  echo "$SERVICE concluido: $FULL_IMAGE"
done

echo ""
echo "Todas as imagens foram enviadas com sucesso!"
