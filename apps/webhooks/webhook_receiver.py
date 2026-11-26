"""Partner webhook receiver (API Gateway HTTP API -> Lambda). SYNTHETIC DEMO.

Verifies X-Nimbus-Signature: hex(HMAC-SHA256(secret, raw_body)) with a
constant-time compare. The shared secret lives in AWS Secrets Manager.
"""

import base64
import hashlib
import hmac
import json
import os
import time
import uuid

import boto3

SECRET_ARN = os.environ.get("WEBHOOK_SECRET_ARN", "")
EVENTS_TABLE = os.environ.get("EVENTS_TABLE", "")

_secret_cache = {}


def _secret() -> bytes:
    if "v" not in _secret_cache:
        sm = boto3.client("secretsmanager")
        _secret_cache["v"] = sm.get_secret_value(SecretId=SECRET_ARN)["SecretString"].encode()
    return _secret_cache["v"]


def _response(code: int, body: dict) -> dict:
    return {"statusCode": code, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}


def handler(event, context):  # noqa: ARG001
    raw = event.get("body") or ""
    body = base64.b64decode(raw) if event.get("isBase64Encoded") else raw.encode()
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    provided = headers.get("x-nimbus-signature", "")

    expected = hmac.new(_secret(), body, hashlib.sha256).hexdigest()
    if not provided or not hmac.compare_digest(expected, provided):
        return _response(401, {"error": "invalid signature", "algorithm": "HMAC-SHA256"})

    event_id = f"EVT-{uuid.uuid4().hex[:12].upper()}"
    if EVENTS_TABLE:
        boto3.client("dynamodb").put_item(
            TableName=EVENTS_TABLE,
            Item={"token_id": {"S": event_id}, "received_at": {"N": str(int(time.time()))}},
        )
    return _response(202, {"accepted": event_id, "algorithm": "HMAC-SHA256", "data_class": "SYNTHETIC"})
