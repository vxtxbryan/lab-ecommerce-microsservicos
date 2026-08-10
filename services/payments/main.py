from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from enum import Enum
import uuid
import random

app = FastAPI(title="Payments Service", version="1.0.0")

payments_db = {}


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
    payment = payments_db.get(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    return payment


@app.post("/payments", response_model=PaymentOut, status_code=201)
def process_payment(payment: PaymentRequest):
    # Simulacao de processamento: 90% de aprovacao, 10% de recusa.
    # Em um cenario real, aqui teria integracao com um gateway (Stripe, PagSeguro etc)
    status = PaymentStatus.approved if random.random() < 0.9 else PaymentStatus.declined

    payment_id = str(uuid.uuid4())
    payment_out = PaymentOut(
        id=payment_id,
        order_id=payment.order_id,
        amount=payment.amount,
        method=payment.method,
        status=status,
    )
    payments_db[payment_id] = payment_out
    return payment_out
