"""Health-check Lambda handler.

Triggered by API Gateway (REST API, Lambda proxy integration) on /health. It:
  1. logs the incoming event to CloudWatch,
  2. validates that the JSON body contains a "payload" key (else HTTP 400),
  3. saves the request to DynamoDB under a generated unique id, and
  4. returns HTTP 200 with a JSON status body.

Runtime: python3.13. Uses only boto3, which ships with the Lambda runtime, so
the deployment package has no third-party dependencies.
"""

import base64
import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

TABLE_NAME = os.environ["TABLE_NAME"]

# Created once per execution environment so warm invocations reuse the client.
_table = boto3.resource("dynamodb").Table(TABLE_NAME)


def _response(status_code: int, body: dict) -> dict:
    """Build an API Gateway proxy response."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    # 1. Log the incoming event for traceability/audit.
    logger.info("Incoming event: %s", json.dumps(event, default=str))

    try:
        # 2. Validate input. The body must be JSON containing a "payload" key.
        raw_body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            raw_body = base64.b64decode(raw_body).decode("utf-8")
        body = json.loads(raw_body)

        if not isinstance(body, dict) or "payload" not in body:
            logger.warning("Rejected request: missing 'payload' key")
            return _response(
                400, {"status": "bad_request", "message": "Missing required key: payload"}
            )

        # 3. Persist the request with a generated unique id. payload is stored as
        #    a JSON string to avoid DynamoDB float/Decimal coercion surprises.
        item = {
            "id": str(uuid.uuid4()),
            "received_at": datetime.now(timezone.utc).isoformat(),
            "source_ip": event.get("requestContext", {})
            .get("identity", {})
            .get("sourceIp", "unknown"),
            "http_method": event.get("httpMethod", "unknown"),
            "ttl": int(time.time()) + 30 * 24 * 60 * 60,  # auto-expire after 30 days
            "payload": json.dumps(body["payload"]),
        }
        _table.put_item(Item=item)
        logger.info("Saved request id=%s", item["id"])

        # 4. Return 200 OK.
        return _response(
            200, {"status": "healthy", "message": "Request processed and saved."}
        )

    except json.JSONDecodeError:
        logger.warning("Rejected request: invalid JSON body")
        return _response(400, {"status": "bad_request", "message": "Invalid JSON body."})
    except Exception:
        # Never leak a stack trace to the caller.
        logger.exception("Unhandled error")
        return _response(500, {"status": "error", "message": "Internal server error."})
