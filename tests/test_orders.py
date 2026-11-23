import asyncio
from unittest.mock import AsyncMock, patch

import httpx
import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from services.orders import main as orders


def pedido(quantity=1):
    return orders.OrderCreate(
        user_id="u", product_id="p", quantity=quantity, payment_method="pix"
    )


@pytest.mark.parametrize("quantity", [0, -1])
def test_quantidade_deve_ser_positiva(quantity):
    with pytest.raises(ValidationError):
        pedido(quantity)


@pytest.mark.parametrize("service", ["users", "products", "payments"])
def test_erro_http_interrompe_pedido(service):
    client = AsyncMock()
    ok = httpx.Response(200, json={"stock": 1, "price": 10, "name": "Livro"})
    error = httpx.Response(500)
    client.get.return_value = error if service == "users" else ok
    client.put.return_value = error if service == "products" else ok
    client.post.return_value = error
    with patch.object(orders.httpx, "AsyncClient") as factory:
        factory.return_value.__aenter__.return_value = client
        with pytest.raises(HTTPException) as exc:
            asyncio.run(orders.create_order(pedido()))
    assert exc.value.status_code == 502
    assert client.get.await_count == 1
    assert client.put.await_count == (0 if service == "users" else 1)
    assert client.post.await_count == (1 if service == "payments" else 0)
