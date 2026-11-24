#!/usr/bin/env bash
# O ALB é interno. O cliente do teste roda dentro da VPC.
set -euo pipefail
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].hostname}' ingress/orders -n default --timeout=8m
dns=$(kubectl get ingress orders -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl exec -i -n default deployment/orders -- python - "$dns" <<'PY'
import sys
import time
import uuid

import httpx

url = f"http://{sys.argv[1]}/orders"
with httpx.Client(timeout=10, trust_env=False) as client:
    deadline = time.monotonic() + 300
    while True:
        try:
            response = client.get(url)
            if response.status_code == 200:
                break
            detail = f"HTTP {response.status_code}"
        except httpx.RequestError as error:
            detail = str(error)
        if time.monotonic() >= deadline:
            raise SystemExit(f"ALB indisponível: {detail}")
        time.sleep(5)

    def create(endpoint, payload, **kwargs):
        response = client.post(endpoint, json=payload, **kwargs)
        response.raise_for_status()
        assert response.status_code == 201
        return response.json()

    key = str(uuid.uuid4())
    user = create("http://users/users", {"name": "Teste ALB", "email": f"{key}@example.com",
                                         "password": str(uuid.uuid4())})
    product = create("http://products/products", {"name": "Livro", "stock": 2, "price": 20})
    payload = {"user_id": user["id"], "product_id": product["id"], "quantity": 1, "payment_method": "pix"}
    headers = {"Idempotency-Key": key}
    order = create(url, payload, headers=headers)
    assert order["status"] in {"confirmed", "payment_declined"} and order["payment_id"]
    assert create(url, payload, headers=headers) == order
    assert client.get(f"http://{sys.argv[1]}/users").status_code == 404
    print(f"ALB {sys.argv[1]}: pedido {order['id']} ({order['status']}), replay idêntico e /users HTTP 404")
PY
