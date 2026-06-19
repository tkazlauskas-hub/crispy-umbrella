provider "aws" {
  region = var.aws_region

  # Tag every resource consistently for cost allocation and ownership.
  default_tags {
    tags = local.common_tags
  }
}
