output "account_id" {
  description = "AWS account the estate was deployed into."
  value       = data.aws_caller_identity.current.account_id
}

output "cloudfront_url" {
  description = "CloudFront edge (default cert, TLSv1 minimum - finding)."
  value       = "https://${aws_cloudfront_distribution.edge.domain_name}"
}

output "api_gateway_webhook_url" {
  description = "Partner webhook endpoint (POST, HMAC-SHA256 signed)."
  value       = "${aws_apigatewayv2_api.webhooks.api_endpoint}/webhooks/partner"
}

output "unauthenticated_lambda_url" {
  description = "Public Lambda Function URL with auth NONE (finding, synthetic data)."
  value       = aws_lambda_function_url.quick_export.function_url
}

output "ec2_public_ip" {
  description = "Elastic IP of the demo host."
  value       = aws_eip.host.public_ip
}

output "ec2_instance_id" {
  description = "Instance ID (use with: aws ssm start-session --target <id>)."
  value       = aws_instance.host.id
}

output "modern_api_url" {
  description = "Modern payment API behind nginx TLS 1.3 (self-signed ECDSA P-256)."
  value       = "https://${aws_eip.host.public_ip}/health"
}

output "legacy_tls10_url" {
  description = "Legacy core on TLS 1.0/1.1 + 3DES (finding)."
  value       = "https://${aws_eip.host.public_ip}:8443/"
}

output "legacy_mysql_endpoint" {
  description = "Legacy MySQL endpoint (public only when enable_legacy_exposure = true)."
  value       = var.enable_legacy_exposure ? "${aws_eip.host.public_ip}:3306" : "localhost-only (enable_legacy_exposure = false)"
}

output "rds_endpoint" {
  description = "RDS Postgres 16 endpoint (private, force_ssl)."
  value       = aws_db_instance.ledger.endpoint
}

output "s3_bucket" {
  description = "KMS-encrypted data bucket."
  value       = aws_s3_bucket.data.bucket
}

output "dynamodb_table" {
  description = "KMS-encrypted DynamoDB table."
  value       = aws_dynamodb_table.tokens.name
}

output "kms_key_arns" {
  description = "KMS keys by role."
  value = {
    data_aes256          = aws_kms_key.data.arn
    partner_rsa2048      = aws_kms_key.partner_signing.arn
    token_ecc_p256       = aws_kms_key.token_signing.arn
    post_quantum_signing = aws_kms_key.pq_signing.arn
  }
}

output "pq_key_spec" {
  description = "Key spec used for the post-quantum key."
  value       = var.pq_key_spec
}

output "secret_arns" {
  description = "Secrets Manager secrets."
  value = {
    rds_master       = aws_secretsmanager_secret.rds_master.arn
    webhook_hmac     = aws_secretsmanager_secret.webhook_hmac.arn
    acquirer_api_key = aws_secretsmanager_secret.acquirer_api_key.arn
  }
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.consumers.id
}

output "cognito_hosted_ui" {
  description = "Cognito hosted UI base URL."
  value       = "https://${aws_cognito_user_pool_domain.consumers.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "unencrypted_ebs_volume_id" {
  description = "Unencrypted 20 GB legacy data volume (finding)."
  value       = aws_ebs_volume.legacy_data.id
}
