"""Compra completa por HTTP; execute apenas contra um ambiente de testes."""
import os
from uuid import uuid4

import httpx
import pytest


@pytest.mark.skipif(
    not all(os.getenv(key) for key in (
        "ORDERS_TEST_URL", "USERS_TEST_URL", "STOCK_TEST_URL", "PAYMENT_TEST_URL"
    )),
    reason="requires all four running APIs",
)
def test_checkout_and_idempotent_retry():
    with httpx.Client(timeout=15) as client:
        def get(url):
            response = client.get(url)
            response.raise_for_status()
            return response.json()

        def create(url, body, **kwargs):
            response = client.post(url, json=body, **kwargs)
            assert response.status_code == 201, response.text
            return response.json()

        user = create(os.environ["USERS_TEST_URL"] + "/users", {
            "name": "Checkout CI", "email": f"checkout-{uuid4()}@example.com",
            "password": "test-password",
        })
        product = create(os.environ["STOCK_TEST_URL"] + "/products", {
            "name": "Checkout CI", "price": 12.5, "stock": 3,
        })
        payload = {"user_id": user["id"], "product_id": product["id"],
                   "quantity": 2, "payment_method": "pix"}
        headers = {"Idempotency-Key": str(uuid4())}
        url = os.environ["ORDERS_TEST_URL"] + "/orders"
        order = create(url, payload, headers=headers)
        assert order["user_id"] == user["id"]
        assert order["product_id"] == product["id"]
        assert order["quantity"] == 2
        assert order["total_price"] == 25
        assert order["status"] in {"confirmed", "payment_declined"}
        payment_url = os.environ["PAYMENT_TEST_URL"] + "/payments/" + order["payment_id"]
        payment = get(payment_url)
        assert payment["order_id"] == order["id"]
        assert payment["amount"] == 25
        assert payment["method"] == "pix"
        approved = order["status"] == "confirmed"
        assert payment["status"] == ("approved" if approved else "declined")
        product_url = os.environ["STOCK_TEST_URL"] + "/products/" + product["id"]
        expected_stock = 1 if approved else 3
        assert get(product_url)["stock"] == expected_stock

        assert create(url, payload, headers=headers) == order
        conflict = client.post(url, json={**payload, "quantity": 1}, headers=headers)
        assert conflict.status_code == 409, conflict.text
        assert get(product_url)["stock"] == expected_stock
        assert get(payment_url) == payment
        assert [item for item in get(url) if item["id"] == order["id"]] == [order]
