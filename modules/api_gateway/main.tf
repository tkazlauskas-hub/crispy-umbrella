# REST API exposing GET/POST /health, integrated with the Lambda via AWS_PROXY.
# A REST API is used (rather than an HTTP API) because it supports native API
# keys + usage plans and request-body validation, both required here.

resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = "Health-check API (${var.stage_name})"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "health"
}

# JSON-schema model that requires a "payload" key, plus a body validator. This
# rejects malformed POST bodies at the edge so they never reach the Lambda.
resource "aws_api_gateway_model" "health_request" {
  rest_api_id  = aws_api_gateway_rest_api.this.id
  name         = "HealthRequest"
  content_type = "application/json"
  schema = jsonencode({
    "$schema"            = "http://json-schema.org/draft-04/schema#"
    title                = "HealthRequest"
    type                 = "object"
    required             = ["payload"]
    properties           = { payload = {} }
    additionalProperties = true
  })
}

resource "aws_api_gateway_request_validator" "body" {
  name                        = "${var.api_name}-body-validator"
  rest_api_id                 = aws_api_gateway_rest_api.this.id
  validate_request_body       = true
  validate_request_parameters = false
}

# --- POST: validated against the model -------------------------------------
resource "aws_api_gateway_method" "post" {
  rest_api_id          = aws_api_gateway_rest_api.this.id
  resource_id          = aws_api_gateway_resource.health.id
  http_method          = "POST"
  authorization        = "NONE"
  api_key_required     = var.api_key_required
  request_validator_id = aws_api_gateway_request_validator.body.id
  request_models       = { "application/json" = aws_api_gateway_model.health_request.name }
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# --- GET --------------------------------------------------------------------
resource "aws_api_gateway_method" "get" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.health.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = var.api_key_required
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# --- Access logging ---------------------------------------------------------
resource "aws_cloudwatch_log_group" "access" {
  name              = "/${var.api_name}-access"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Redeploy when any part of the API surface changes.
  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.health.id,
      aws_api_gateway_method.get.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.get.id,
      aws_api_gateway_integration.post.id,
      aws_api_gateway_request_validator.body.id,
      aws_api_gateway_model.health_request.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      apiKeyId       = "$context.identity.apiKeyId"
    })
  }

  tags = var.tags
}

# Throttling (DDoS protection) and execution logging/metrics for every method.
resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.throttle_rate
    throttling_burst_limit = var.throttle_burst
    metrics_enabled        = true
    logging_level          = "INFO"
  }
}

# --- API key + usage plan (authentication + per-key throttling/quota) -------
resource "aws_api_gateway_api_key" "this" {
  count = var.api_key_required ? 1 : 0
  name  = "${var.api_name}-key"
  tags  = var.tags
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "${var.api_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  throttle_settings {
    rate_limit  = var.throttle_rate
    burst_limit = var.throttle_burst
  }

  quota_settings {
    limit  = var.quota_limit
    period = "DAY"
  }

  tags = var.tags
}

resource "aws_api_gateway_usage_plan_key" "this" {
  count         = var.api_key_required ? 1 : 0
  key_id        = aws_api_gateway_api_key.this[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}

# --- WAF (defense in depth at the edge) ------------------------------------
# Even with API keys and throttling, a WAF adds IP rate limiting and AWS-managed
# protections (common exploits, known-bad inputs) in front of the API.
resource "aws_wafv2_web_acl" "this" {
  count = var.enable_waf ? 1 : 0
  name  = "${var.api_name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "ip-rate-limit"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.api_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-common-rules"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.api_name}-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.api_name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.api_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}

# --- WAF logging -----------------------------------------------------------
# WAF requires a log group whose name starts with "aws-waf-logs-". A CloudWatch
# Logs resource policy authorises the log-delivery service to write to it.
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "waf" {
  count             = var.enable_waf && var.enable_waf_logging ? 1 : 0
  name              = "aws-waf-logs-${var.api_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

data "aws_iam_policy_document" "waf_logs" {
  count = var.enable_waf && var.enable_waf_logging ? 1 : 0

  statement {
    sid    = "AWSWAFLogsDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf[0].arn}:*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  count           = var.enable_waf && var.enable_waf_logging ? 1 : 0
  policy_name     = "${var.api_name}-waf-logging"
  policy_document = data.aws_iam_policy_document.waf_logs[0].json
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count                   = var.enable_waf && var.enable_waf_logging ? 1 : 0
  resource_arn            = aws_wafv2_web_acl.this[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}
