# nimbus-demo-lite

A small, **Terraform-only** AWS estate for RelixQ demos. It has a modern
fintech side and an intentionally weak "acquired legacy bank" side, so a
RelixQ scan returns cloud, runtime and code crypto findings that you can check
against a written answer key (`ground-truth/findings.csv`).

> All data is **synthetic**. The legacy parts are insecure on purpose. Deploy only
> into a dedicated demo AWS account and destroy the stack when you are done.

You only need **Terraform >= 1.6 and the AWS CLI v2**. There is no WSL, Ansible, CDK,
Helm, Vault or upstream fork. One `terraform apply` builds everything in about 10–15 minutes.
Most of that time is RDS and CloudFront.

## Architecture

```
                         +-------------------- AWS account (1 region) ---------------------+
 Internet ──► CloudFront (default cert, TLSv1 min) ──http:8080──► EC2 t3.small (Ubuntu 24.04)
 Internet ──► :443  nginx TLS 1.3 ─► payment-api (Python)      │  docker compose:
 Internet ──► :8443 nginx 1.14 TLS 1.0/1.1 + 3DES (legacy)     │   payment-api, modern-tls,
 Internet ──► :3306 MySQL 5.7 (legacy, optional)               │   legacy-core, legacy-mysql
                                                               │  + unencrypted 20 GB EBS
 Partner ──► API Gateway HTTP API ─► Lambda webhook-receiver (HMAC-SHA256)
 Anyone  ──► Lambda Function URL (auth NONE) ─► quick-export
             VPC 10.42.0.0/16: public "prod" + "legacy" subnets, IGW, no NAT
             RDS Postgres 16 (private, KMS, force_ssl) · S3 (SSE-KMS) · DynamoDB (SSE-KMS)
             KMS: AES-256 · RSA-2048 · ECC P-256 · ML-DSA-65
             Secrets Manager x3 · SSM SecureString · Cognito user pool + hosted UI · AWS Budget
```

| Folder | Contents |
|---|---|
| `infra/` | A single Terraform stack: `network`, `kms`, `secrets`, `data`, `identity`, `serverless`, `edge`, `compute`, `budget`, `outputs`. Host bootstrap files are in `templates/` |
| `apps/payment-api/` | Modern API: TLS 1.3, SHA-256/HMAC-SHA256, KMS ECDSA signing |
| `apps/legacy-core/` | Legacy nginx config (TLS 1.0, 3DES), a legacy client (MD5, SHA-1, TLSv1, hardcoded password) and MySQL seed data |
| `apps/webhooks/` | Lambda code. Terraform zips it with `archive_file` |
| `ground-truth/findings.csv` | Answer key with 32 findings (modern and legacy) |
| `deploy.ps1` / `deploy.sh` | Runners for Windows PowerShell and for bash |
| `deploy.env.example` | Every parameter, with sample values |

## Deploy

See **[instruction.md](instruction.md)**. In short:

```powershell
Copy-Item deploy.env.example deploy.env    # edit the <-- CHANGE lines
.\deploy.ps1 -Offline preflight render-vars validate
.\deploy.ps1 deploy
.\deploy.ps1 destroy
```

State, tfvars, provider plugins, Lambda zips and `outputs.json` are written under
`STATE_DIR` (default `.state/`), so the source folders stay clean. If you want remote
state, see `infra/backend.s3.tf.example` and `TF_BACKEND_CONFIG`.

## Estimated cost (us-east-1, running all the time)

| Item | ~USD / month |
|---|---|
| EC2 t3.small | 15.2 |
| RDS db.t4g.micro + 20 GB gp3 | 14.0 |
| Public IPv4 (Elastic IP) | 3.7 |
| EBS: 16 GB root + 20 GB legacy (gp3) | 2.9 |
| KMS: 4 customer-managed keys | 4.0 |
| Secrets Manager: 3 secrets | 1.2 |
| CloudFront, API Gateway, Lambda, DynamoDB, S3, Cognito, SSM | < 1 at demo traffic |
| **Total** | **about $40–42 / month (about $1.40 / day)** |

The budget (`MONTHLY_BUDGET_USD`, default 50) emails `OWNER_EMAIL` when actual spend
passes 80% or forecast spend passes 100%. To spend nothing between demos, run
`.\deploy.ps1 destroy`. KMS keys are then scheduled for deletion after 7 days.

## What RelixQ should find

**Modern (good posture):**
- KMS AES-256 with key rotation
- ML-DSA-65 post-quantum signing key
- TLS 1.3-only API with an ECDSA P-256 certificate
- HMAC-SHA256 webhooks with constant-time compare
- RDS `force_ssl`
- SSE-KMS on S3, DynamoDB, Secrets Manager and SSM
- IMDSv2 required on the EC2 host

**Quantum-vulnerable (needs PQC migration):**
- RSA-2048 KMS partner signing key
- ECC P-256 KMS token signing key and ECDSA in the payment API

**Legacy (intentional findings):**
- TLS 1.0/1.1 with 3DES/CBC on :8443
- RSA-1024/SHA-1 certificate valid for 10 years
- CloudFront viewer minimum protocol TLSv1
- HTTP-only CloudFront origin
- Unauthenticated Lambda Function URL
- Unencrypted 20 GB EBS volume
- MySQL 5.7 exposed on :3306
- MySQL root password in EC2 user_data
- MD5 PINs and 3DES PANs in the seed data
- MD5, SHA-1, TLSv1, `CERT_NONE` and a hardcoded keystore password in `legacy_client.py`

`ground-truth/findings.csv` has the full list with resource, layer, algorithm and severity.

## Post-quantum key note

`PQ_KEY_SPEC=ML_DSA_65` was checked against the pinned AWS provider (`~> 6.0`).
Version 6.74 accepts `ML_DSA_44/65/87`. If your region does not offer ML-DSA in KMS
yet, set `PQ_KEY_SPEC=ECC_NIST_P384` (or `RSA_4096`) and run deploy again.
