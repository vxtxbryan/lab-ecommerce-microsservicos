from common.telemetry import configure_telemetry
from decimal import Decimal
import os
from threading import Lock
from uuid import UUID, uuid4

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, PositiveInt

app = FastAPI(title="Products Service", version="1.0.0")
configure_telemetry(app, "products")
products_db = {}
reservation_receipts = {}
lock = Lock()


def products_table():
    name = os.getenv("PRODUCTS_TABLE")
    if name:
        # Resources do boto3 são locais à chamada (as rotas usam threads).
        return boto3.resource("dynamodb", endpoint_url=os.getenv("DYNAMODB_ENDPOINT")).Table(name)


class Product(BaseModel):
    name: str
    price: float = Field(ge=0, allow_inf_nan=False)
    stock: int = Field(ge=0)


class ProductOut(Product):
    id: str


class Reservation(BaseModel):
    quantity: PositiveInt


@app.get("/health")
def health():
    return {"status": "ok", "service": "products"}


@app.get("/products", response_model=list[ProductOut])
def list_products():
    table = products_table()
    if table is None:
        with lock:
            return [item.copy() for item in products_db.values()]
    page = table.scan(FilterExpression="attribute_not_exists(receipt)")
    items = page["Items"]
    while "LastEvaluatedKey" in page:
        page = table.scan(FilterExpression="attribute_not_exists(receipt)", ExclusiveStartKey=page["LastEvaluatedKey"])
        items.extend(page["Items"])
    return items


@app.get("/products/{product_id}", response_model=ProductOut)
def get_product(product_id: str):
    table = products_table()
    if table is None:
        with lock:
            product = products_db.get(product_id, {}).copy()
    else:
        product = table.get_item(Key={"id": product_id}, ConsistentRead=True).get("Item")
    if not product or product.get("receipt"):
        raise HTTPException(404, "Product not found")
    return product


@app.post("/products", response_model=ProductOut, status_code=201)
def create_product(product: Product):
    item = dict(product.model_dump(), id=str(uuid4()), reservations={})
    table = products_table()
    if table is None:
        with lock:
            products_db[item["id"]] = item
    else:
        item["price"] = Decimal(str(product.price))
        table.put_item(Item=item)
    return item


@app.put("/products/{product_id}/reservations/{order_id}", response_model=ProductOut)
def reserve(product_id: str, order_id: UUID, reservation: Reservation):
    key = str(order_id)
    quantity = reservation.quantity
    table = products_table()
    receipt_id = f"reservation#{product_id}#{key}"

    def replay(receipt):
        if receipt["quantity"] != quantity:
            raise HTTPException(409, "Reserva com quantidade diferente")
        return receipt["product"]

    if table is None:
        with lock:
            if receipt_id in reservation_receipts:
                return replay(reservation_receipts[receipt_id])
            item = products_db.get(product_id)
            if item is None:
                raise HTTPException(404, "Product not found")
            if item["stock"] < quantity:
                raise HTTPException(409, "Reserva indisponível")
            item["stock"] -= quantity
            item["reservations"][key] = quantity
            snapshot = ProductOut.model_validate(item).model_dump()
            reservation_receipts[receipt_id] = {"product": snapshot, "quantity": quantity}
            return snapshot

    def read_receipt():
        return table.get_item(Key={"id": receipt_id}, ConsistentRead=True).get("Item")

    if receipt := read_receipt():
        return replay(receipt)
    # Compare o saldo lido para gravar o snapshot exato na mesma transação.
    for _ in range(5):
        item = get_product(product_id)
        if item["stock"] < quantity:
            if receipt := read_receipt():
                return replay(receipt)
            raise HTTPException(409, "Reserva indisponível")
        snapshot = {field: item[field] for field in ("id", "name", "price", "stock")}
        snapshot["stock"] -= quantity
        receipt = {"id": receipt_id, "receipt": True, "product": snapshot, "quantity": quantity}
        try:
            table.meta.client.transact_write_items(TransactItems=[
                {"Put": {"TableName": table.name, "Item": receipt,
                         "ConditionExpression": "attribute_not_exists(id)"}},
                {"Update": {"TableName": table.name, "Key": {"id": product_id},
                            "UpdateExpression": "SET stock = stock - :q, reservations.#order = :q",
                            "ConditionExpression": "stock = :previous AND attribute_not_exists(reservations.#order)",
                            "ExpressionAttributeNames": {"#order": key},
                            "ExpressionAttributeValues": {":q": quantity, ":previous": item["stock"]}}},
            ])
            return snapshot
        except table.meta.client.exceptions.TransactionCanceledException:
            if existing := read_receipt():
                return replay(existing)
    raise HTTPException(503, "Conflito temporário ao reservar estoque")


@app.delete("/products/{product_id}/reservations/{order_id}", status_code=204)
def settle(product_id: str, order_id: UUID, restore: bool):
    key = str(order_id)
    table = products_table()
    if table is None:
        with lock:
            item = products_db.get(product_id)
            if item:
                quantity = item["reservations"].pop(key, 0)
                if restore:
                    item["stock"] += quantity
        return
    update = "REMOVE reservations.#order"
    if restore:
        update = "SET stock = stock + reservations.#order " + update
    try:
        table.update_item(
            Key={"id": product_id},
            UpdateExpression=update,
            ConditionExpression="attribute_exists(reservations.#order)",
            ExpressionAttributeNames={"#order": key},
        )
    except ClientError as error:
        if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
            raise


@app.delete("/products/{product_id}", status_code=204)
def delete_product(product_id: str):
    table = products_table()
    if table is None:
        with lock:
            item = products_db.get(product_id)
            if item is None:
                raise HTTPException(404, "Product not found")
            if item["reservations"]:
                raise HTTPException(409, "Reservas pendentes")
            del products_db[product_id]
        return
    try:
        table.delete_item(Key={"id": product_id}, ConditionExpression="size(reservations) = :zero",
                          ExpressionAttributeValues={":zero": 0})
    except ClientError as error:
        if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
            raise
        get_product(product_id)
        raise HTTPException(409, "Reservas pendentes") from error
