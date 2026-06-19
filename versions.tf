terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Partial backend configuration. The bucket, key, region and lock table are
  # supplied at init time via -backend-config (see the Makefile and CI). Using
  # Terraform workspaces isolates staging and prod state within the bucket.
  backend "s3" {
    key     = "health-check/terraform.tfstate"
    encrypt = true
  }
}
