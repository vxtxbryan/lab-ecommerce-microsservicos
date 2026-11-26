from common.telemetry import configure_telemetry
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from enum import Enum
from decimal import Decimal
from threading import Lock
import os
import boto3
import uuid
import random

app = FastAPI(title="Payments Service", version="1.0.0")
configure_telemetry(app, "payments")

payments_db = {}
lock = Lock()


def payments_table():
    if name := os.getenv("PAYMENTS_TABLE"):
        return boto3.resource("dynamodb", endpoint_url=os.getenv("DYNAMODB_ENDPOINT")).Table(name)


class PaymentMethod(str, Enum):
    credit_card = "credit_card"
    pix = "pix"
    boleto = "boleto"


class PaymentStatus(str, Enum):
    approved = "approved"
    declined = "declined"


class PaymentRequest(BaseModel):
    order_id: str
    amount: float
    method: PaymentMethod


class PaymentOut(BaseModel):
    id: str
    order_id: str
    amount: float
    method: PaymentMethod
    status: PaymentStatus


@app.get("/health")
def health():
    return {"status": "ok", "service": "payments"}


@app.get("/payments/{payment_id}", response_model=PaymentOut)
def get_payment(payment_id: str):
    table = payments_table()
    if table is None:
        payment = payments_db.get(payment_id)
    else:
        payment = table.get_item(Key={"id": payment_id}, ConsistentRead=True).get("Item")
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    return payment


@app.post("/payments", response_model=PaymentOut, status_code=201)
def process_payment(payment: PaymentRequest):
    # Simulacao de processamento: 90% de aprovacao, 10% de recusa.
    # Em um cenario real, aqui teria integracao com um gateway (Stripe, PagSeguro etc)
    status = PaymentStatus.approved if random.random() < 0.9 else PaymentStatus.declined

    payment_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "ecommerce/payment/" + payment.order_id))
    payment_out = PaymentOut(
        id=payment_id,
        order_id=payment.order_id,
        amount=payment.amount,
        method=payment.method,
        status=status,
    )
    item = payment_out.model_dump(mode="json")
    item["amount"] = Decimal(str(payment.amount))
    table = payments_table()
    if table is None:
        with lock:
            stored = payments_db.setdefault(payment_id, item)
    else:
        try:
            table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
            stored = item
        except table.meta.client.exceptions.ConditionalCheckFailedException:
            stored = table.get_item(Key={"id": payment_id}, ConsistentRead=True)["Item"]
    if stored["amount"] != item["amount"] or stored["method"] != item["method"]:
        raise HTTPException(409, "Pedido já possui pagamento com outros parâmetros")
    return stored
