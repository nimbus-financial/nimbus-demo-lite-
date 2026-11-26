terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = var.aws_account_id == "" ? null : [var.aws_account_id]

  default_tags {
    tags = {
      Project     = var.project_prefix
      Environment = "demo"
      ManagedBy   = "terraform"
      DataClass   = "synthetic"
      Purpose     = "relixq-demo"
    }
  }
}
