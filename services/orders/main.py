from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from enum import Enum
import httpx
import uuid
import os

app = FastAPI(title="Orders Service", version="1.0.0")

orders_db = {}

PRODUCTS_SERVICE_URL = os.getenv("PRODUCTS_SERVICE_URL", "http://localhost:8000")
USERS_SERVICE_URL = os.getenv("USERS_SERVICE_URL", "http://localhost:8002")
PAYMENTS_SERVICE_URL = os.getenv("PAYMENTS_SERVICE_URL", "http://localhost:8003")


class PaymentMethod(str, Enum):
    credit_card = "credit_card"
    pix = "pix"
    boleto = "boleto"


class OrderCreate(BaseModel):
    user_id: str
    product_id: str
    quantity: int
    payment_method: PaymentMethod


class OrderOut(BaseModel):
    id: str
    user_id: str
    product_id: str
    product_name: str
    quantity: int
    total_price: float
    status: str
    payment_id: str | None = None


@app.get("/health")
def health():
    return {"status": "ok", "service": "orders"}


@app.get("/orders", response_model=list[OrderOut])
def list_orders():
    return list(orders_db.values())


@app.post("/orders", response_model=OrderOut, status_code=201)
async def create_order(order: OrderCreate):
    async with httpx.AsyncClient(timeout=5.0) as client:

        # 1. Valida o usuario
        try:
            user_response = await client.get(f"{USERS_SERVICE_URL}/users/{order.user_id}")
        except httpx.RequestError:
            raise HTTPException(status_code=503, detail="Users service indisponivel")

        if user_response.status_code == 404:
            raise HTTPException(status_code=404, detail="Usuario nao encontrado")

        # 2. Valida o produto e estoque
        try:
            product_response = await client.get(f"{PRODUCTS_SERVICE_URL}/products/{order.product_id}")
        except httpx.RequestError:
            raise HTTPException(status_code=503, detail="Products service indisponivel")

        if product_response.status_code == 404:
            raise HTTPException(status_code=404, detail="Produto nao encontrado")

        product = product_response.json()

        if product["stock"] < order.quantity:
            raise HTTPException(status_code=400, detail="Estoque insuficiente")

        total_price = product["price"] * order.quantity
        order_id = str(uuid.uuid4())

        # 3. Processa o pagamento
        try:
            payment_response = await client.post(
                f"{PAYMENTS_SERVICE_URL}/payments",
                json={
                    "order_id": order_id,
                    "amount": total_price,
                    "method": order.payment_method.value,
                },
            )
        except httpx.RequestError:
            raise HTTPException(status_code=503, detail="Payments service indisponivel")

        payment = payment_response.json()
        final_status = "confirmed" if payment["status"] == "approved" else "payment_declined"

    order_out = OrderOut(
        id=order_id,
        user_id=order.user_id,
        product_id=order.product_id,
        product_name=product["name"],
        quantity=order.quantity,
        total_price=total_price,
        status=final_status,
        payment_id=payment["id"],
    )
    orders_db[order_id] = order_out
    return order_out
