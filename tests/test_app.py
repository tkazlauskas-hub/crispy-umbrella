"""Unit tests for the health-check handler (DynamoDB mocked with moto)."""

import importlib
import json

import boto3
import pytest
from moto import mock_aws

TABLE = "test-requests-db"
REGION = "eu-central-1"


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    monkeypatch.setenv("TABLE_NAME", TABLE)
    monkeypatch.setenv("AWS_DEFAULT_REGION", REGION)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")


@pytest.fixture
def table():
    with mock_aws():
        res = boto3.resource("dynamodb", region_name=REGION)
        res.create_table(
            TableName=TABLE,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield res.Table(TABLE)


def _load():
    # "lambda" is a reserved word, so the package cannot be imported with the
    # import statement; importlib.import_module takes the name as a string.
    mod = importlib.import_module("lambda.app")
    return importlib.reload(mod)


def _event(body, method="POST", b64=False):
    return {
        "httpMethod": method,
        "isBase64Encoded": b64,
        "body": body,
        "requestContext": {"identity": {"sourceIp": "203.0.113.10"}},
    }


def test_valid_request_returns_200_and_saves(table):
    app = _load()
    resp = app.handler(_event(json.dumps({"payload": {"check": "ok"}})), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["status"] == "healthy"
    assert table.scan()["Count"] == 1


def test_missing_payload_returns_400(table):
    app = _load()
    resp = app.handler(_event(json.dumps({"foo": "bar"})), None)
    assert resp["statusCode"] == 400
    assert table.scan()["Count"] == 0


def test_invalid_json_returns_400(table):
    app = _load()
    resp = app.handler(_event("not-json"), None)
    assert resp["statusCode"] == 400
