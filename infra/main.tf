locals {
  name          = var.project_prefix
  apps_dir      = var.apps_dir != "" ? var.apps_dir : "${path.module}/../apps"
  artifacts_dir = var.artifacts_dir != "" ? var.artifacts_dir : "${path.module}/.artifacts"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
