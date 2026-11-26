# Diverse key types so RelixQ's cryptographic inventory has something to find.

resource "aws_kms_key" "data" {
  description              = "${local.name} AES-256 data encryption key"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  deletion_window_in_days  = 7

  tags = { Name = "${local.name}-data", CryptoRole = "data-encryption" }
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}

resource "aws_kms_key" "partner_signing" {
  description              = "${local.name} RSA-2048 partner signing key (quantum-vulnerable)"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "RSA_2048"
  deletion_window_in_days  = 7

  tags = { Name = "${local.name}-partner-rsa2048", CryptoRole = "partner-signing" }
}

resource "aws_kms_alias" "partner_signing" {
  name          = "alias/${local.name}-partner-rsa2048"
  target_key_id = aws_kms_key.partner_signing.key_id
}

resource "aws_kms_key" "token_signing" {
  description              = "${local.name} ECC P-256 token signing key (quantum-vulnerable)"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7

  tags = { Name = "${local.name}-token-p256", CryptoRole = "token-signing" }
}

resource "aws_kms_alias" "token_signing" {
  name          = "alias/${local.name}-token-p256"
  target_key_id = aws_kms_key.token_signing.key_id
}

resource "aws_kms_key" "pq_signing" {
  description              = "${local.name} post-quantum signing key (${var.pq_key_spec})"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = var.pq_key_spec
  deletion_window_in_days  = 7

  tags = { Name = "${local.name}-pq-signing", CryptoRole = "pq-signing" }
}

resource "aws_kms_alias" "pq_signing" {
  name          = "alias/${local.name}-pq-signing"
  target_key_id = aws_kms_key.pq_signing.key_id
}
