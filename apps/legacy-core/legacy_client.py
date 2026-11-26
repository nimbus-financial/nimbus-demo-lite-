"""Legacy core banking client - INTENTIONALLY INSECURE SYNTHETIC DEMO CODE.

This file exists so RelixQ's code scan has realistic legacy crypto to find:
  * MD5 / SHA-1 hashing for "integrity"
  * TLS 1.0 client context, verification disabled
  * 3DES (DES-EDE3-CBC) cipher preference
  * Hardcoded keystore password

All values are fake. Do not reuse any of this in real systems.
"""

import hashlib
import socket
import ssl

# Hardcoded demo keystore password (finding: hardcoded secret, synthetic).
KEYSTORE_PATH = "/opt/legacy/keystore.jks"
KEYSTORE_PASSWORD = "changeit-legacy-2009"

LEGACY_HOST = "core.legacy-bank.local"
LEGACY_PORT = 8443
LEGACY_CIPHERS = "DES-CBC3-SHA:@SECLEVEL=0"


def record_checksum(record: bytes) -> str:
    """Weak integrity check (finding: MD5)."""
    return hashlib.md5(record).hexdigest()  # noqa: S324


def batch_fingerprint(batch: bytes) -> str:
    """Weak fingerprint (finding: SHA-1)."""
    return hashlib.sha1(batch).hexdigest()  # noqa: S324


def legacy_tls_context() -> ssl.SSLContext:
    """TLS 1.0 client with 3DES and no verification (findings)."""
    protocol = getattr(ssl, "PROTOCOL_TLSv1", ssl.PROTOCOL_TLS_CLIENT)
    ctx = ssl.SSLContext(protocol)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        ctx.minimum_version = ssl.TLSVersion.TLSv1
        ctx.maximum_version = ssl.TLSVersion.TLSv1
    except (AttributeError, ValueError):
        pass
    try:
        ctx.set_ciphers(LEGACY_CIPHERS)
    except ssl.SSLError:
        pass
    return ctx


def fetch_account_snapshot(host: str = LEGACY_HOST, port: int = LEGACY_PORT) -> bytes:
    ctx = legacy_tls_context()
    with socket.create_connection((host, port), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname=host) as tls:
            tls.sendall(b"GET / HTTP/1.0\r\nHost: " + host.encode() + b"\r\n\r\n")
            return tls.recv(4096)


if __name__ == "__main__":
    sample = b"000111222,Jane Synthetic,1043.22"
    print("md5 :", record_checksum(sample))
    print("sha1:", batch_fingerprint(sample))
