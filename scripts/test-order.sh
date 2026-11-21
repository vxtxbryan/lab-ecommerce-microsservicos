#!/bin/bash
# Teste de ponta a ponta: cria um usuário e um produto e faz um pedido.
#
# Funciona tanto com o Docker Compose quanto com o cluster (via kubectl
# port-forward), porque nos dois casos os serviços ficam em localhost:
#   products :8000 | orders :8001 | users :8002
#
# Uso:  ./scripts/test-order.sh
# Para apontar para outros endereços, sobrescreva as variáveis:
#   ORDERS_URL=http://localhost:9001 ./scripts/test-order.sh
set -euo pipefail

USERS_URL="${USERS_URL:-http://localhost:8002}"
PRODUCTS_URL="${PRODUCTS_URL:-http://localhost:8000}"
ORDERS_URL="${ORDERS_URL:-http://localhost:8001}"

# Faz um POST com JSON. Imprime o corpo da resposta; se o status HTTP não for
# 2xx (ou se não conseguir conectar), mostra o erro e encerra o script.
post_json() {
  local url="$1" payload="$2" out code body
  out=$(curl -s -w '\n%{http_code}' -X POST "$url" \
    -H 'Content-Type: application/json' -d "$payload") || {
    echo "Erro: não foi possível conectar em $url" >&2
    echo "Os serviços estão no ar? (docker compose up / kubectl port-forward)" >&2
    exit 1
  }
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  if [[ "$code" != 2* ]]; then
    echo "Erro HTTP $code em $url: $body" >&2
    exit 1
  fi
  printf '%s' "$body"
}

json_field() {
  python3 -c 'import sys, json; print(json.load(sys.stdin)["'"$1"'"])'
}

echo "1/3 Criando usuário..."
EMAIL="teste-$(date +%s)-$RANDOM@exemplo.com"
RESP=$(post_json "$USERS_URL/users" \
  "{\"name\":\"Teste\",\"email\":\"$EMAIL\",\"password\":\"123456\"}")
USER_ID=$(printf '%s' "$RESP" | json_field id)
echo "    user_id=$USER_ID"

echo "2/3 Criando produto..."
RESP=$(post_json "$PRODUCTS_URL/products" \
  '{"name":"Teclado","price":150.0,"stock":10}')
PRODUCT_ID=$(printf '%s' "$RESP" | json_field id)
echo "    product_id=$PRODUCT_ID"

echo "3/3 Criando pedido (orders chama users, products e payments)..."
RESP=$(post_json "$ORDERS_URL/orders" \
  "{\"user_id\":\"$USER_ID\",\"product_id\":\"$PRODUCT_ID\",\"quantity\":2,\"payment_method\":\"pix\"}")
printf '%s' "$RESP" | python3 -m json.tool

echo
echo "status=confirmed        -> pagamento aprovado (cerca de 90% das vezes)"
echo "status=payment_declined -> recusa simulada pelo serviço payments (cerca de 10%)"
