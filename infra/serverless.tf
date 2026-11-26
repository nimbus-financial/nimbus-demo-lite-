# Lambdas are packaged straight from apps/webhooks by archive_file - no npm, no CDK.

data "archive_file" "webhook_receiver" {
  type        = "zip"
  source_file = "${local.apps_dir}/webhooks/webhook_receiver.py"
  output_path = "${local.artifacts_dir}/webhook_receiver.zip"
}

data "archive_file" "quick_export" {
  type        = "zip"
  source_file = "${local.apps_dir}/webhooks/quick_export.py"
  output_path = "${local.artifacts_dir}/quick_export.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_access" {
  statement {
    sid       = "ReadWebhookSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.webhook_hmac.arn]
  }

  statement {
    sid       = "DecryptWithDataKey"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
  }

  statement {
    sid       = "WriteWebhookEvents"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.tokens.arn]
  }
}

resource "aws_iam_role_policy" "lambda_access" {
  name   = "${local.name}-lambda-access"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_access.json
}

resource "aws_lambda_function" "webhook_receiver" {
  function_name    = "${local.name}-webhook-receiver"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "webhook_receiver.handler"
  filename         = data.archive_file.webhook_receiver.output_path
  source_code_hash = data.archive_file.webhook_receiver.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      WEBHOOK_SECRET_ARN = aws_secretsmanager_secret.webhook_hmac.arn
      EVENTS_TABLE       = aws_dynamodb_table.tokens.name
    }
  }
}

resource "aws_lambda_function" "quick_export" {
  function_name    = "${local.name}-quick-export"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "quick_export.handler"
  filename         = data.archive_file.quick_export.output_path
  source_code_hash = data.archive_file.quick_export.output_base64sha256
  timeout          = 10
  memory_size      = 128
}

# Intentional finding: unauthenticated Function URL (synthetic data only).
resource "aws_lambda_function_url" "quick_export" {
  function_name      = aws_lambda_function.quick_export.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "quick_export_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.quick_export.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# Since Oct 2025 a public Function URL also needs lambda:InvokeFunction.
resource "aws_lambda_permission" "quick_export_invoke" {
  statement_id             = "AllowPublicInvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.quick_export.function_name
  principal                = "*"
  invoked_via_function_url = true
}

# ---------------------------------------------------------------- API Gateway

resource "aws_apigatewayv2_api" "webhooks" {
  name          = "${local.name}-webhooks"
  protocol_type = "HTTP"
  description   = "Partner webhook ingress (HMAC-SHA256 verified)"
}

resource "aws_apigatewayv2_integration" "webhook_receiver" {
  api_id                 = aws_apigatewayv2_api.webhooks.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.webhook_receiver.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "partner_webhook" {
  api_id    = aws_apigatewayv2_api.webhooks.id
  route_key = "POST /webhooks/partner"
  target    = "integrations/${aws_apigatewayv2_integration.webhook_receiver.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhooks.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_webhook" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_receiver.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhooks.execution_arn}/*/*"
}
