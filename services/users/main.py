from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext
import uuid

app = FastAPI(title="Users Service", version="1.0.0")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

users_db = {}


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
    return [
        UserOut(id=u["id"], name=u["name"], email=u["email"])
        for u in users_db.values()
    ]


@app.get("/users/{user_id}", response_model=UserOut)
def get_user(user_id: str):
    user = users_db.get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserOut(id=user["id"], name=user["name"], email=user["email"])


@app.post("/users", response_model=UserOut, status_code=201)
def create_user(user: UserCreate):
    for existing in users_db.values():
        if existing["email"] == user.email:
            raise HTTPException(status_code=400, detail="Email ja cadastrado")

    user_id = str(uuid.uuid4())
    hashed_password = pwd_context.hash(user.password)

    users_db[user_id] = {
        "id": user_id,
        "name": user.name,
        "email": user.email,
        "hashed_password": hashed_password,
    }

    return UserOut(id=user_id, name=user.name, email=user.email)


@app.post("/users/login")
def login(credentials: LoginRequest):
    for user in users_db.values():
        if user["email"] == credentials.email:
            if pwd_context.verify(credentials.password, user["hashed_password"]):
                return {"message": "Login bem-sucedido", "user_id": user["id"]}
            raise HTTPException(status_code=401, detail="Senha incorreta")

    raise HTTPException(status_code=404, detail="Usuario nao encontrado")
