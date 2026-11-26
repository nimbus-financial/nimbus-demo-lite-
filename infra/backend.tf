# Local state by default. deploy.ps1 / deploy.sh pass
#   -backend-config=path=<STATE_DIR>/terraform.tfstate
# at init time, so state never lands inside the repo.
# To use S3 instead, see backend.s3.tf.example.
terraform {
  backend "local" {}
}
