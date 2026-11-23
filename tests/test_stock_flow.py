"""Run with STOCK_TEST_URL pointing to the local products API."""
import asyncio
import os
from unittest.mock import patch

import httpx
import pytest

from services.orders import main as orders


@pytest.mark.skipif(not os.getenv("STOCK_TEST_URL"), reason="requires running products API")
def test_last_unit_and_declined_payment():
    asyncio.run(exercise_stock_flow())


async def exercise_stock_flow():
    # Products uses real HTTP and DynamoDB. Simulate only identity and payment
    # so the two payment outcomes are deterministic.
    async with httpx.AsyncClient(base_url=os.environ["STOCK_TEST_URL"]) as products:
        created = await products.post("/products", json={"name": "Livro", "stock": 1, "price": 10})
        created.raise_for_status()
        path = "/products/" + created.json()["id"]
        payment_status = "declined"
        charges = []

        async def route(request):
            if request.url.host == "users":
                return httpx.Response(200, json={"id": "u"})
            if request.url.host == "payments":
                charges.append(payment_status)
                return httpx.Response(201, json={"id": "p", "status": payment_status})
            return await products.request(request.method, request.url.raw_path.decode(),
                                          content=request.content, headers={"Content-Type": "application/json"})

        client_class = httpx.AsyncClient
        transport = httpx.MockTransport(route)
        api = httpx.ASGITransport(app=orders.app)
        body = {"user_id": "u", "product_id": created.json()["id"], "quantity": 1, "payment_method": "pix"}
        async with client_class(transport=api, base_url="http://orders") as caller:
            with patch.multiple(orders, USERS_SERVICE_URL="http://users", PRODUCTS_SERVICE_URL="http://products",
                                PAYMENTS_SERVICE_URL="http://payments"), patch.object(
                orders.httpx, "AsyncClient", side_effect=lambda **kw: client_class(transport=transport, **kw)
            ):
                declined = await caller.post("/orders", json=body)
                assert declined.json()["status"] == "payment_declined"
                assert (await products.get(path)).json()["stock"] == 1
                payment_status = "approved"
                results = await asyncio.gather(*(caller.post("/orders", json=body) for _ in range(2)))
                assert sorted(response.status_code for response in results) == [201, 400]
                assert charges == ["declined", "approved"]
                assert (await products.get(path)).json()["stock"] == 0
        (await products.delete(path)).raise_for_status()


@pytest.mark.skipif(not os.getenv("PAYMENT_TEST_URL") or not os.getenv("STOCK_TEST_URL"),
                    reason="requires running products and payments APIs")
def test_retry_after_lost_payment_response():
    asyncio.run(retry_after_lost_response())


async def retry_after_lost_response():
    from uuid import uuid4

    client_class = httpx.AsyncClient
    async with client_class(base_url=os.environ["STOCK_TEST_URL"]) as products, client_class(
        base_url=os.environ["PAYMENT_TEST_URL"]
    ) as payments:
        created = await products.post("/products", json={"name": "Livro", "stock": 1, "price": 10})
        created.raise_for_status()
        product_id = created.json()["id"]
        payment_results = []

        async def route(request):
            if request.url.host == "users":
                return httpx.Response(200)
            service = payments if request.url.host == "payments" else products
            response = await service.request(request.method, request.url.raw_path.decode(),
                                             content=request.content, headers={"Content-Type": "application/json"})
            if service is payments:
                response.raise_for_status()
                payment_results.append(response.json())
                if len(payment_results) == 1:
                    raise httpx.ReadTimeout("Resposta perdida após persistir pagamento", request=request)
            return response

        payload = {"user_id": "u", "product_id": product_id, "quantity": 1, "payment_method": "pix"}
        headers = {"Idempotency-Key": str(uuid4())}
        transport = httpx.MockTransport(route)
        async with client_class(transport=httpx.ASGITransport(app=orders.app), base_url="http://orders") as api:
            with patch.multiple(orders, USERS_SERVICE_URL="http://users", PRODUCTS_SERVICE_URL="http://products",
                                PAYMENTS_SERVICE_URL="http://payments"), patch.object(
                orders.httpx, "AsyncClient", side_effect=lambda **kw: client_class(transport=transport, **kw)
            ):
                assert (await api.post("/orders", json=payload, headers=headers)).status_code == 503
                recovered = await api.post("/orders", json=payload, headers=headers)
                recovered.raise_for_status()
                assert len(payment_results) == 2
                assert payment_results[0] == payment_results[1]
                assert recovered.json()["payment_id"] == payment_results[0]["id"]
                expected_stock = 0 if payment_results[0]["status"] == "approved" else 1
                assert (await products.get(f"/products/{product_id}")).json()["stock"] == expected_stock
        (await products.delete(f"/products/{product_id}")).raise_for_status()
