"""Inicializa as tabelas de desenvolvimento no DynamoDB Local."""
import os

import boto3

db = boto3.resource("dynamodb", endpoint_url=os.environ["DYNAMODB_ENDPOINT"])
for name in ("products", "orders", "payments", "users"):
    table = db.Table(name)
    try:
        table.load()
    except db.meta.client.exceptions.ResourceNotFoundException:
        table = db.create_table(
            TableName=table.name,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
    table.wait_until_exists()
