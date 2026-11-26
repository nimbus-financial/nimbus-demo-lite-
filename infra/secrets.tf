resource "random_password" "rds_master" {
  length           = 32
  special          = true
  override_special = "!#%^*-_=+"
}

resource "random_password" "webhook_hmac" {
  length  = 48
  special = false
}

resource "random_password" "acquirer_api_key" {
  length  = 40
  special = false
}

# Intentionally weak: legacy MySQL root password is rendered into EC2 user_data.
resource "random_password" "legacy_mysql" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "rds_master" {
  name                    = "${local.name}/rds/master"
  description             = "RDS Postgres master credentials (synthetic demo)"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id
  secret_string = jsonencode({
    username = "nimbus_admin"
    password = random_password.rds_master.result
    engine   = "postgres"
    port     = 5432
  })
}

resource "aws_secretsmanager_secret" "webhook_hmac" {
  name                    = "${local.name}/webhooks/hmac"
  description             = "HMAC-SHA256 shared secret for partner webhooks (synthetic demo)"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "webhook_hmac" {
  secret_id     = aws_secretsmanager_secret.webhook_hmac.id
  secret_string = random_password.webhook_hmac.result
}

resource "aws_secretsmanager_secret" "acquirer_api_key" {
  name                    = "${local.name}/acquirer/api-key"
  description             = "Card acquirer API key (synthetic demo)"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "acquirer_api_key" {
  secret_id     = aws_secretsmanager_secret.acquirer_api_key.id
  secret_string = random_password.acquirer_api_key.result
}

resource "aws_ssm_parameter" "partner_config" {
  name        = "/${local.name}/partner/config"
  description = "Partner integration config (synthetic demo)"
  type        = "SecureString"
  key_id      = aws_kms_key.data.arn
  value = jsonencode({
    partner_id       = "acme-acquirer-demo"
    signing_alg      = "RSASSA_PKCS1_V1_5_SHA_256"
    signing_key      = aws_kms_alias.partner_signing.name
    webhook_hmac_alg = "HMAC-SHA256"
  })
}
