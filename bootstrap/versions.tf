terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Bootstrap intentionally uses LOCAL state: it creates the very S3 backend and
  # lock table that the main configuration consumes (a chicken-and-egg that must
  # be broken locally). Run once by an administrator with elevated credentials.
  # Store the resulting local state file securely (or migrate it into the bucket
  # afterwards). Nothing here is environment-specific.
}
