locals {
  name_prefix = var.environment

  common_tags = merge(
    {
      Project            = "homework-health-check"
      Environment        = var.environment
      ManagedBy          = "terraform"
      Owner              = "platform-engineering"
      CostCenter         = var.cost_center
      DataClassification = var.data_classification
      Compliance         = "DORA"
    },
    var.extra_tags,
  )

  # env-resource-name convention.
  table_name    = "${var.environment}-requests-db"
  function_name = "${var.environment}-health-check-function"
  api_name      = "${var.environment}-health-check-api"
}
