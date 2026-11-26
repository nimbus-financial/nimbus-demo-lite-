variable "project_prefix" {
  description = "Name prefix for every resource (lowercase letters, digits, hyphens)."
  type        = string
  default     = "nimbus-demo-lite"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_prefix))
    error_message = "project_prefix must be 3-25 chars: lowercase letters, digits, hyphens."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "Expected AWS account ID. The provider refuses to run against any other account. Empty = no check (validate only)."
  type        = string
  default     = ""
}

variable "owner_email" {
  description = "Email that receives budget alerts."
  type        = string
  default     = "ops@example.com"
}

variable "bucket_suffix" {
  description = "Globally unique suffix appended to the S3 bucket name, e.g. -123456789012-demo."
  type        = string
  default     = "-demo"
}

variable "cognito_domain_prefix" {
  description = "Globally unique Cognito hosted UI domain prefix."
  type        = string
  default     = "nimbus-demo-lite-auth"
}

variable "instance_type" {
  description = "EC2 instance type for the single demo host."
  type        = string
  default     = "t3.small"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "enable_budget" {
  description = "Create an AWS Budget that emails owner_email."
  type        = bool
  default     = true
}

variable "monthly_budget_usd" {
  description = "Monthly budget limit in USD."
  type        = number
  default     = 50
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the demo host ports (443, 8443, 3306). Use your IP/32 or 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.allowed_cidr, 0))
    error_message = "allowed_cidr must be a valid IPv4 CIDR, e.g. 203.0.113.10/32."
  }
}

variable "enable_legacy_exposure" {
  description = "Expose the legacy MySQL container on :3306 to allowed_cidr (intentional finding)."
  type        = bool
  default     = true
}

variable "pq_key_spec" {
  description = "Key spec for the post-quantum signing key. ML_DSA_65 by default; use ECC_NIST_P384 or RSA_4096 if the region lacks ML-DSA."
  type        = string
  default     = "ML_DSA_65"

  validation {
    condition     = contains(["ML_DSA_44", "ML_DSA_65", "ML_DSA_87", "ECC_NIST_P384", "RSA_4096"], var.pq_key_spec)
    error_message = "pq_key_spec must be ML_DSA_44, ML_DSA_65, ML_DSA_87, ECC_NIST_P384 or RSA_4096."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.42.0.0/16"
}

variable "apps_dir" {
  description = "Path to the apps/ folder (Lambda + host code). Empty = ../apps relative to this stack."
  type        = string
  default     = ""
}

variable "artifacts_dir" {
  description = "Folder for generated Lambda zip files. Empty = <stack>/.artifacts."
  type        = string
  default     = ""
}
