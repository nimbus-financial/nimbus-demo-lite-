"""Quick merchant export - INTENTIONALLY EXPOSED via an unauthenticated Lambda
Function URL (authorization_type = NONE). SYNTHETIC DEMO DATA ONLY.
"""

import json

MERCHANTS = [
    {"merchant_id": "MRC-1001", "name": "Synthetic Coffee Co", "mcc": "5814", "settlement_acct": "XXXX-1111"},
    {"merchant_id": "MRC-1002", "name": "Demo Books Ltd", "mcc": "5942", "settlement_acct": "XXXX-2222"},
    {"merchant_id": "MRC-1003", "name": "Fake Fuel Stop", "mcc": "5541", "settlement_acct": "XXXX-3333"},
]


def handler(event, context):  # noqa: ARG001
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"data_class": "SYNTHETIC", "auth": "NONE", "merchants": MERCHANTS}),
    }
