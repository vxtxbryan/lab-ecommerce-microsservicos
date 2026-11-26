from common.telemetry import configure_telemetry
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext
from threading import Lock
import os
import uuid

import boto3

app = FastAPI(title="Users Service", version="1.0.0")
configure_telemetry(app, "users")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

users_db = {}
lock = Lock()


def users_table():
    if name := os.getenv("USERS_TABLE"):
        return boto3.resource("dynamodb", endpoint_url=os.getenv("DYNAMODB_ENDPOINT")).Table(name)


def id_for_email(email: str):
    # EmailStr já normaliza o domínio. Preserve a parte local, como no login.
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "ecommerce/users/" + email))


def read_user(user_id: str):
    table = users_table()
    if table is None:
        with lock:
            return users_db.get(user_id)
    return table.get_item(Key={"id": user_id}, ConsistentRead=True).get("Item")


class UserCreate(BaseModel):
    name: str
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: str
    name: str
    email: EmailStr


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


@app.get("/health")
def health():
    return {"status": "ok", "service": "users"}


@app.get("/users", response_model=list[UserOut])
def list_users():
    table = users_table()
    if table is None:
        with lock:
            return list(users_db.values())
    options = {"ProjectionExpression": "id, #name, email", "ExpressionAttributeNames": {"#name": "name"}}
    users = []
    while True:
        page = table.scan(**options)
        users.extend(page["Items"])
        if "LastEvaluatedKey" not in page:
            return users
        options["ExclusiveStartKey"] = page["LastEvaluatedKey"]


@app.get("/users/{user_id}", response_model=UserOut)
def get_user(user_id: str):
    user = read_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserOut(id=user["id"], name=user["name"], email=user["email"])


@app.post("/users", response_model=UserOut, status_code=201)
def create_user(user: UserCreate):
    user_id = id_for_email(user.email)
    item = {
        "id": user_id,
        "name": user.name,
        "email": user.email,
        "hashed_password": pwd_context.hash(user.password),
    }
    table = users_table()
    if table is None:
        with lock:
            if user_id in users_db:
                raise HTTPException(400, "Email ja cadastrado")
            users_db[user_id] = item
    else:
        try:
            table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
        except table.meta.client.exceptions.ConditionalCheckFailedException as error:
            raise HTTPException(400, "Email ja cadastrado") from error

    return UserOut(id=user_id, name=user.name, email=user.email)


@app.post("/users/login")
def login(credentials: LoginRequest):
    user = read_user(id_for_email(credentials.email))
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    if not pwd_context.verify(credentials.password, user["hashed_password"]):
        raise HTTPException(status_code=401, detail="Senha incorreta")
    return {"message": "Login bem-sucedido", "user_id": user["id"]}
