"""Nimbus Payment API (modern) - SYNTHETIC DEMO for RelixQ.

Clean, modern crypto posture:
  * Served behind nginx with TLS 1.3 only (see nginx-modern.conf)
  * SHA-256 / HMAC-SHA256 for integrity
  * AWS KMS ECC_NIST_P256 (ECDSA_SHA_256) for token signing
  * Secrets from AWS Secrets Manager, never hardcoded

Standard library only; boto3 is used when available.
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import boto3  # type: ignore
except ImportError:  # pragma: no cover
    boto3 = None

REGION = os.environ.get("AWS_REGION", "us-east-1")
TOKEN_KEY_ID = os.environ.get("TOKEN_SIGNING_KEY_ID", "")
ACQUIRER_SECRET_ARN = os.environ.get("ACQUIRER_SECRET_ARN", "")
TOKENS_TABLE = os.environ.get("TOKENS_TABLE", "")
PORT = int(os.environ.get("PORT", "8080"))

SIGNING_ALGORITHM = "ECDSA_SHA_256"
_acquirer_key_cache = {}


def _client(service):
    if boto3 is None:
        return None
    return boto3.client(service, region_name=REGION)


def acquirer_key() -> bytes:
    """Fetch the acquirer API key from Secrets Manager (cached)."""
    if "v" not in _acquirer_key_cache:
        value = None
        sm = _client("secretsmanager")
        if sm is not None and ACQUIRER_SECRET_ARN:
            try:
                value = sm.get_secret_value(SecretId=ACQUIRER_SECRET_ARN)["SecretString"]
            except Exception:  # noqa: BLE001
                value = None
        _acquirer_key_cache["v"] = (value or secrets.token_hex(32)).encode()
    return _acquirer_key_cache["v"]


def kms_sign(message: bytes) -> dict:
    """Sign a SHA-256 digest with the KMS ECC P-256 key."""
    kms = _client("kms")
    digest = hashlib.sha256(message).digest()
    if kms is None or not TOKEN_KEY_ID:
        return {"algorithm": SIGNING_ALGORITHM, "signature": None, "note": "kms unavailable"}
    try:
        resp = kms.sign(
            KeyId=TOKEN_KEY_ID,
            Message=digest,
            MessageType="DIGEST",
            SigningAlgorithm=SIGNING_ALGORITHM,
        )
        return {"algorithm": SIGNING_ALGORITHM, "signature": base64.b64encode(resp["Signature"]).decode()}
    except Exception as exc:  # noqa: BLE001
        return {"algorithm": SIGNING_ALGORITHM, "signature": None, "note": str(exc)[:120]}


def checkout(payload: dict) -> dict:
    txn = {
        "txn_id": f"TXN-{uuid.uuid4().hex[:12].upper()}",
        "merchant_id": payload.get("merchant_id", "MRC-1001"),
        "amount_usd": payload.get("amount_usd", 42.50),
        "currency": "USD",
        "card_token": "tok_" + secrets.token_urlsafe(16),
        "ts": int(time.time()),
        "data_class": "SYNTHETIC",
    }
    body = json.dumps(txn, sort_keys=True).encode()
    txn["integrity"] = {
        "sha256": hashlib.sha256(body).hexdigest(),
        "hmac_sha256": hmac.new(acquirer_key(), body, hashlib.sha256).hexdigest(),
    }
    txn["kms_signature"] = kms_sign(body)
    ddb = _client("dynamodb")
    if ddb is not None and TOKENS_TABLE:
        try:
            ddb.put_item(
                TableName=TOKENS_TABLE,
                Item={"token_id": {"S": txn["card_token"]}, "txn_id": {"S": txn["txn_id"]}},
            )
        except Exception:  # noqa: BLE001
            pass
    return txn


class Handler(BaseHTTPRequestHandler):
    server_version = "NimbusPaymentAPI/1.0"

    def _send(self, code: int, obj: dict) -> None:
        data = json.dumps(obj, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Strict-Transport-Security", "max-age=31536000")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        if self.path in ("/", "/health"):
            self._send(200, {"service": "nimbus-payment-api", "status": "ok", "data_class": "SYNTHETIC"})
        elif self.path == "/crypto":
            self._send(200, {
                "tls": "TLSv1.3 (nginx front end)",
                "integrity": ["SHA-256", "HMAC-SHA256"],
                "signing": {"kms_key": TOKEN_KEY_ID or "unset", "algorithm": SIGNING_ALGORITHM},
                "secrets": "AWS Secrets Manager",
            })
        elif self.path == "/checkout":
            self._send(200, checkout({}))
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path != "/checkout":
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid json"})
            return
        self._send(201, checkout(payload))


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
