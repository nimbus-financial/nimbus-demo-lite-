# nimbus-demo-lite: quick deploy

**Prerequisites (Windows):** Terraform 1.6 or newer and AWS CLI v2. You also need an AWS account that is used only for demos.

```powershell
winget install Hashicorp.Terraform
winget install Amazon.AWSCLI
```

## 1. Set parameters

```powershell
cd C:\relixq-demo\nimbus-demo-lite
Copy-Item deploy.env.example deploy.env
notepad deploy.env          # edit every line marked  <-- CHANGE
```

| Parameter | Sample value | Notes |
|---|---|---|
| `REPO_ROOT` | `C:\relixq-demo\nimbus-demo-lite` | Leave empty to use the script's folder |
| `INFRA_DIR` / `APPS_DIR` | `${REPO_ROOT}/infra` / `${REPO_ROOT}/apps` | |
| `STATE_DIR` / `ARTIFACTS_DIR` | `${REPO_ROOT}/.state` / `${STATE_DIR}/artifacts` | Keep `STATE_DIR` fixed after the first deploy |
| `AWS_PROFILE` / `AWS_REGION` | `nimbus-demo` / `us-east-1` | |
| `AWS_ACCOUNT_ID` | `123456789012` | **Must be your real account.** The script refuses to run against any other account |
| `OWNER_EMAIL` | `ops@example.com` | Budget alerts go here |
| `PROJECT_PREFIX` | `nimbus-demo-lite` | |
| `BUCKET_SUFFIX` | `-123456789012-demo` | Must be globally unique |
| `COGNITO_DOMAIN_PREFIX` | `nimbus-demo-lite-auth-2026` | Must be globally unique |
| `INSTANCE_TYPE` / `DB_INSTANCE_CLASS` | `t3.small` / `db.t4g.micro` | |
| `ENABLE_BUDGET` / `MONTHLY_BUDGET_USD` | `true` / `50` | |
| `ALLOWED_CIDR` | `0.0.0.0/0` | Prefer your own IP, e.g. `203.0.113.10/32` |
| `ENABLE_LEGACY_EXPOSURE` | `true` | Opens MySQL :3306 to `ALLOWED_CIDR` |
| `PQ_KEY_SPEC` | `ML_DSA_65` | Fallback: `ECC_NIST_P384` |
| `AUTO_APPROVE` | `false` | `true` works the same as `-Yes` |

## 2. Log in to AWS

```powershell
aws configure sso --profile nimbus-demo     # or: aws configure --profile nimbus-demo
aws sso login --profile nimbus-demo
```

## 3. Check, deploy, use

```powershell
.\deploy.ps1 -Offline preflight render-vars validate   # no AWS calls
.\deploy.ps1 preflight                                 # checks that your credentials match AWS_ACCOUNT_ID
.\deploy.ps1 plan                                      # optional
.\deploy.ps1 deploy                                    # type "yes" when prompted, or add -Yes
.\deploy.ps1 outputs                                   # URLs, also saved to .state\outputs.json
```

If PowerShell blocks the script, run
`powershell -ExecutionPolicy Bypass -File .\deploy.ps1 deploy` or
`Unblock-File .\deploy.ps1`.

Wait about 5 minutes after apply for the EC2 host to finish starting its containers. Then:

```powershell
curl.exe -k https://<ec2_public_ip>/health                # modern API, TLS 1.3
curl.exe -k --tlsv1.0 --tls-max 1.0 https://<ec2_public_ip>:8443/   # legacy TLS 1.0
curl.exe <unauthenticated_lambda_url>                     # public Function URL
aws ssm start-session --target <ec2_instance_id>          # shell on the host (needs the Session Manager plugin)
```

Point RelixQ at the account and region, plus this folder for the code scan. Compare its results with `ground-truth\findings.csv`.

## 4. Tear down

```powershell
.\deploy.ps1 destroy          # type the project prefix to confirm, or add -Yes
```

## Git Bash / WSL / Linux / macOS

Use the same commands with `./deploy.sh` and `--offline` / `--yes`. For example:
`./deploy.sh --offline preflight render-vars validate`, then `./deploy.sh deploy`.

Cost is about $40/month if left running. Destroy the stack between demos.
