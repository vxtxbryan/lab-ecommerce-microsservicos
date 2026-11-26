#!/bin/bash
# Build e push manual das imagens para o ECR.
# Normalmente quem faz isso e a CI; use este script para o primeiro envio
# ou para testes locais.
#
# Variaveis opcionais:
#   AWS_REGION   (padrao: us-east-1)
#   PROJECT_NAME (padrao: ecommerce-microsservicos)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-ecommerce-microsservicos}"

# O ID da conta vem das credenciais em uso (nada hardcoded)
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Tag idêntica à CI. Publique apenas revisões commitadas.
GIT_SHA="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Faça commit das alterações antes de publicar imagens." >&2
  exit 1
fi

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

echo "Conta AWS: ${AWS_ACCOUNT_ID} | Regiao: ${AWS_REGION} | Tag: ${GIT_SHA}"
echo "Fazendo login no ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

for SERVICE in "${SERVICES[@]}"; do
  echo ""
  echo "=== Processando $SERVICE ==="

  IMAGE_NAME="${PROJECT_NAME}-${SERVICE}"
  REPO="${ECR_REGISTRY}/${IMAGE_NAME}"

  echo "Buildando imagem..."
  docker build -t "${IMAGE_NAME}:${GIT_SHA}" -f "services/${SERVICE}/Dockerfile" .

  echo "Aplicando tags para o ECR..."
  docker tag "${IMAGE_NAME}:${GIT_SHA}" "${REPO}:${GIT_SHA}"

  echo "Enviando para o ECR..."
  push_with_retry "${REPO}:${GIT_SHA}"

  echo "$SERVICE concluido: ${REPO}:${GIT_SHA}"
done

echo ""
echo "Todas as imagens foram enviadas com sucesso!"
