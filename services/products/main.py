from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import uuid

app = FastAPI(title="Products Service", version="1.0.0")

# Em memória por enquanto — trocamos por Postgres/RDS depois
products_db = {}


class Product(BaseModel):
    name: str
    price: float
    stock: int


class ProductOut(Product):
    id: str


@app.get("/health")
def health():
    return {"status": "ok", "service": "products"}


@app.get("/products", response_model=list[ProductOut])
def list_products():
    return list(products_db.values())


@app.get("/products/{product_id}", response_model=ProductOut)
def get_product(product_id: str):
    product = products_db.get(product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@app.post("/products", response_model=ProductOut, status_code=201)
def create_product(product: Product):
    product_id = str(uuid.uuid4())
    product_out = ProductOut(id=product_id, **product.dict())
    products_db[product_id] = product_out
    return product_out


@app.delete("/products/{product_id}", status_code=204)
def delete_product(product_id: str):
    if product_id not in products_db:
        raise HTTPException(status_code=404, detail="Product not found")
    del products_db[product_id]
