from common.telemetry import configure_telemetry
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel, PositiveInt
from enum import Enum
from decimal import Decimal
from typing import Annotated
import boto3
import httpx
import uuid
import os

app = FastAPI(title="Orders Service", version="1.0.0")
configure_telemetry(app, "orders")

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
    quantity: PositiveInt
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


def orders_table():
    if name := os.getenv("ORDERS_TABLE"):
        return boto3.resource("dynamodb", endpoint_url=os.getenv("DYNAMODB_ENDPOINT")).Table(name)


@app.get("/orders", response_model=list[OrderOut])
def list_orders():
    table = orders_table()
    if table is None:
        return [item["result"] for item in orders_db.values() if "result" in item]
    results = []
    options = {"FilterExpression": "attribute_exists(#result)",
               "ExpressionAttributeNames": {"#result": "result"}}
    while True:
        page = table.scan(**options)
        results.extend(item["result"] for item in page["Items"])
        if "LastEvaluatedKey" not in page:
            return results
        options["ExclusiveStartKey"] = page["LastEvaluatedKey"]


@app.post("/orders", response_model=OrderOut, status_code=201)
async def create_order(order: OrderCreate, idempotency_key: Annotated[
    str | None, Header(alias="Idempotency-Key", min_length=1, max_length=255)
] = None):
    if idempotency_key is None:
        order_id = str(uuid.uuid4())
    else:
        order_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "ecommerce/order/" + idempotency_key))
    intent = {"id": order_id, "request": order.model_dump(mode="json")}
    table = orders_table()
    if table is None:
        record = orders_db.setdefault(order_id, intent)
    else:
        try:
            table.put_item(Item=intent, ConditionExpression="attribute_not_exists(id)")
            record = intent
        except table.meta.client.exceptions.ConditionalCheckFailedException:
            record = table.get_item(Key={"id": order_id}, ConsistentRead=True)["Item"]
    if record["request"] != intent["request"]:
        raise HTTPException(409, "Idempotency-Key já usada para outro pedido")
    if "result" in record:
        return record["result"]

    async with httpx.AsyncClient(timeout=5.0) as client:
        if not record.get("validated"):
            try:
                user_response = await client.get(f"{USERS_SERVICE_URL}/users/{order.user_id}")
            except httpx.RequestError:
                raise HTTPException(status_code=503, detail="Users service indisponivel")
            if user_response.status_code == 404:
                raise HTTPException(status_code=404, detail="Usuario nao encontrado")
            if not user_response.is_success:
                raise HTTPException(status_code=502, detail="Resposta inesperada de Users")
            if table is None:
                record["validated"] = True
            else:
                table.update_item(Key={"id": order_id}, UpdateExpression="SET validated = :v",
                                  ExpressionAttributeValues={":v": True})

        reservation_url = f"{PRODUCTS_SERVICE_URL}/products/{order.product_id}/reservations/{order_id}"
        try:
            product_response = await client.put(reservation_url, json={"quantity": order.quantity})
        except httpx.RequestError:
            raise HTTPException(status_code=503, detail="Products service indisponivel")

        if product_response.status_code == 404:
            raise HTTPException(status_code=404, detail="Produto nao encontrado")

        if product_response.status_code == 409:
            raise HTTPException(status_code=400, detail="Estoque insuficiente")

        if not product_response.is_success:
            raise HTTPException(status_code=502, detail="Resposta inesperada de Products")

        product = product_response.json()

        total_price = product["price"] * order.quantity

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

        if not payment_response.is_success:
            raise HTTPException(status_code=502, detail="Resposta inesperada de Payments")

        payment = payment_response.json()
        if payment.get("status") not in {"approved", "declined"} or not payment.get("id"):
            raise HTTPException(status_code=502, detail="Pagamento sem resultado válido")
        try:
            settled = await client.delete(reservation_url, params={"restore": payment["status"] == "declined"})
        except httpx.RequestError:
            raise HTTPException(status_code=503, detail="Products service indisponivel")
        if not settled.is_success:
            raise HTTPException(status_code=502, detail="Falha ao finalizar reserva")
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
    result = order_out.model_dump(mode="json")
    result["total_price"] = Decimal(str(order_out.total_price))
    if table is None:
        record["result"] = result
    else:
        table.update_item(Key={"id": order_id}, UpdateExpression="SET #result = :v",
                          ExpressionAttributeNames={"#result": "result"},
                          ExpressionAttributeValues={":v": result})
    return order_out
