data "aws_ssm_parameter" "ubuntu_2404" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "host" {
  name               = "${local.name}-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "host_access" {
  statement {
    sid       = "SignWithKms"
    actions   = ["kms:Sign", "kms:Verify", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = [aws_kms_key.token_signing.arn, aws_kms_key.partner_signing.arn, aws_kms_key.pq_signing.arn]
  }

  statement {
    sid       = "ReadAcquirerSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.acquirer_api_key.arn]
  }

  statement {
    sid       = "DecryptWithDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }

  statement {
    sid       = "PaymentTokens"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.tokens.arn]
  }
}

resource "aws_iam_role_policy" "host_access" {
  name   = "${local.name}-host-access"
  role   = aws_iam_role.host.id
  policy = data.aws_iam_policy_document.host_access.json
}

resource "aws_iam_instance_profile" "host" {
  name = "${local.name}-host"
  role = aws_iam_role.host.name
}

# Intentional finding: acquired-bank data volume without encryption.
resource "aws_ebs_volume" "legacy_data" {
  availability_zone = aws_subnet.prod.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = false

  tags = { Name = "${local.name}-legacy-data", Finding = "unencrypted-ebs" }
}

locals {
  host_files = {
    app_py        = base64gzip(replace(file("${local.apps_dir}/payment-api/app.py"), "\r\n", "\n"))
    nginx_modern  = base64gzip(replace(file("${local.apps_dir}/payment-api/nginx-modern.conf"), "\r\n", "\n"))
    nginx_legacy  = base64gzip(replace(file("${local.apps_dir}/legacy-core/nginx-legacy.conf"), "\r\n", "\n"))
    mysql_seed    = base64gzip(replace(file("${local.apps_dir}/legacy-core/mysql-seed.sql"), "\r\n", "\n"))
    legacy_client = base64gzip(replace(file("${local.apps_dir}/legacy-core/legacy_client.py"), "\r\n", "\n"))
    docker_compose = base64gzip(replace(templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
      aws_region          = var.aws_region
      token_key_id        = aws_kms_key.token_signing.arn
      acquirer_secret_arn = aws_secretsmanager_secret.acquirer_api_key.arn
      tokens_table        = aws_dynamodb_table.tokens.name
      mysql_bind          = var.enable_legacy_exposure ? "0.0.0.0" : "127.0.0.1"
      mysql_root_password = random_password.legacy_mysql.result
    }), "\r\n", "\n"))
    bootstrap = base64gzip(replace(templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
      legacy_volume_id = aws_ebs_volume.legacy_data.id
    }), "\r\n", "\n"))
  }
}

resource "aws_instance" "host" {
  ami                         = data.aws_ssm_parameter.ubuntu_2404.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.prod.id
  vpc_security_group_ids      = [aws_security_group.host.id, aws_security_group.cloudfront_origin.id]
  iam_instance_profile        = aws_iam_instance_profile.host.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = replace(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", local.host_files), "\r\n", "\n")

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${local.name}-host" }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "legacy_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.legacy_data.id
  instance_id = aws_instance.host.id
}

resource "aws_eip" "host" {
  domain   = "vpc"
  instance = aws_instance.host.id

  tags = { Name = "${local.name}-host" }

  depends_on = [aws_internet_gateway.main]
}
