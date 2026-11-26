# ---------------------------------------------------------------- RDS Postgres 16

resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db"
  subnet_ids = [aws_subnet.prod.id, aws_subnet.legacy.id]
}

resource "aws_db_parameter_group" "postgres" {
  name        = "${local.name}-pg16"
  family      = "postgres16"
  description = "Force TLS for all Postgres connections"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "ledger" {
  identifier                 = "${local.name}-ledger"
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = var.db_instance_class
  allocated_storage          = 20
  storage_type               = "gp3"
  storage_encrypted          = true
  kms_key_id                 = aws_kms_key.data.arn
  db_name                    = "ledger"
  username                   = "nimbus_admin"
  password                   = random_password.rds_master.result
  parameter_group_name       = aws_db_parameter_group.postgres.name
  db_subnet_group_name       = aws_db_subnet_group.main.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  publicly_accessible        = false
  multi_az                   = false
  backup_retention_period    = 1
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = { Name = "${local.name}-ledger" }
}

# ---------------------------------------------------------------- S3

resource "aws_s3_bucket" "data" {
  bucket        = "${local.name}-data${var.bucket_suffix}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "settlement_sample" {
  bucket       = aws_s3_bucket.data.id
  key          = "settlements/2026/settlement-sample.csv"
  content_type = "text/csv"
  content      = "txn_id,merchant_id,amount_usd,currency,status\nTXN-0001,MRC-1001,42.50,USD,SETTLED\nTXN-0002,MRC-1002,13.99,USD,SETTLED\nTXN-0003,MRC-1001,250.00,USD,PENDING\n"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.data]
}

# ---------------------------------------------------------------- DynamoDB

resource "aws_dynamodb_table" "tokens" {
  name         = "${local.name}-payment-tokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "token_id"

  attribute {
    name = "token_id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.data.arn
  }

  point_in_time_recovery {
    enabled = false
  }
}
