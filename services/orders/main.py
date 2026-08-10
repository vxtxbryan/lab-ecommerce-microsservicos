from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
import uuid
import os

app = FastAPI(title="Orders Service", version="1.0.0")

orders_db = {}

PRODUCTS_SERVICE_URL = os.getenv("PRODUCTS_SERVICE_URL", "http://localhost:8000")


class OrderCreate(BaseModel):
    product_id: str
    quantity: int


class OrderOut(BaseModel):
    id: str
    product_id: str
    product_name: str
    quantity: int
    total_price: float
    status: str


@app.get("/health")
def health():
    return {"status": "ok", "service": "orders"}


@app.get("/orders", response_model=list[OrderOut])
def list_orders():
    return list(orders_db.values())


@app.post("/orders", response_model=OrderOut, status_code=201)
async def create_order(order: OrderCreate):
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(
                f"{PRODUCTS_SERVICE_URL}/products/{order.product_id}",
                timeout=5.0,
            )
        except httpx.RequestError:
            raise HTTPException(
                status_code=503,
                detail="Products service indisponivel"
            )

    if response.status_code == 404:
        raise HTTPException(status_code=404, detail="Produto nao encontrado")

    product = response.json()

    if product["stock"] < order.quantity:
        raise HTTPException(status_code=400, detail="Estoque insuficiente")

    order_id = str(uuid.uuid4())
    order_out = OrderOut(
        id=order_id,
        product_id=order.product_id,
        product_name=product["name"],
        quantity=order.quantity,
        total_price=product["price"] * order.quantity,
        status="confirmed",
    )
    orders_db[order_id] = order_out
    return order_out
