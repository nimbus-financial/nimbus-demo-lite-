resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

# "prod" subnet: modern workloads. "legacy" subnet: acquired-bank workloads.
# Both are public (no NAT gateway, keeps cost low). They sit in two AZs so the
# RDS subnet group is valid.
resource "aws_subnet" "prod" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-prod", Tier = "prod" }
}

resource "aws_subnet" "legacy" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-legacy", Tier = "legacy" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "prod" {
  subnet_id      = aws_subnet.prod.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "legacy" {
  subnet_id      = aws_subnet.legacy.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------- security groups

resource "aws_security_group" "host" {
  name        = "${local.name}-host"
  description = "Demo host: modern TLS 1.3 API, legacy TLS 1.0 core, legacy MySQL"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-host" }
}

resource "aws_vpc_security_group_ingress_rule" "host_https" {
  security_group_id = aws_security_group.host.id
  description       = "Modern payment API (TLS 1.3)"
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "host_legacy_tls" {
  security_group_id = aws_security_group.host.id
  description       = "Legacy core (TLS 1.0/1.1 + 3DES) - intentional finding"
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 8443
  to_port           = 8443
}

resource "aws_vpc_security_group_ingress_rule" "host_mysql" {
  count = var.enable_legacy_exposure ? 1 : 0

  security_group_id = aws_security_group.host.id
  description       = "Legacy MySQL exposed - intentional finding"
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 3306
  to_port           = 3306
}

resource "aws_vpc_security_group_egress_rule" "host_all" {
  security_group_id = aws_security_group.host.id
  description       = "All outbound (package installs, AWS APIs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Separate SG for the CloudFront origin rule: the managed prefix list counts as
# ~55 rules, so it gets its own group.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "cloudfront_origin" {
  name        = "${local.name}-cf-origin"
  description = "CloudFront origin-facing access to the payment API on 8080"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-cf-origin" }
}

resource "aws_vpc_security_group_ingress_rule" "cf_origin_http" {
  security_group_id = aws_security_group.cloudfront_origin.id
  description       = "CloudFront to payment API"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "Postgres reachable only from the demo host"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_host" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres from demo host"
  referenced_security_group_id = aws_security_group.host.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
