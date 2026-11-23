"""Teste HTTP contra users com DynamoDB Local no Compose."""
import os
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import httpx
import pytest


@pytest.mark.skipif(not os.getenv("USERS_TEST_URL"), reason="requires running users API")
def test_concurrent_signup_and_login():
    email = f"{uuid4()}@example.com"
    signups = [
        {"email": email, "name": name, "password": str(uuid4())}
        for name in ("Ana", "Bia")
    ]
    with httpx.Client(base_url=os.environ["USERS_TEST_URL"], timeout=10) as client:
        with ThreadPoolExecutor(2) as pool:
            responses = list(pool.map(lambda body: client.post("/users", json=body), signups))
        assert sorted(response.status_code for response in responses) == [201, 400]
        winner = next(i for i, response in enumerate(responses) if response.status_code == 201)
        user = responses[winner].json()
        assert set(user) == {"id", "name", "email"}
        assert client.get(f"/users/{user['id']}").json() == user
        listed = client.get("/users")
        listed.raise_for_status()
        assert [row for row in listed.json() if row["email"] == email] == [user]
        for i, signup in enumerate(signups):
            login = client.post("/users/login", json={"email": email, "password": signup["password"]})
            if i == winner:
                login.raise_for_status()
                assert login.json()["user_id"] == user["id"]
            else:
                assert login.status_code == 401
