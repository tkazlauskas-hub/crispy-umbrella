# Private-only VPC for the Lambda function. There is deliberately no internet
# gateway and no NAT gateway: the function never talks to the public internet.
# It reaches AWS services through VPC endpoints, which keeps traffic on the AWS
# network and removes a class of data-exfiltration paths.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-${count.index + 1}" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group for the Lambda ENIs: no inbound, egress limited to HTTPS within
# the VPC (all an AWS service endpoint needs). No 0.0.0.0/0 egress.
resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-lambda-sg"
  description = "Lambda egress to in-VPC AWS service endpoints only"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-lambda-sg" })
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to AWS service endpoints inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

# Security group for the interface endpoint(s): allow HTTPS only from the Lambda
# security group.
resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "Allow HTTPS from Lambda SG to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from the Lambda security group"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.lambda.id
}

# Gateway endpoint for DynamoDB (no hourly cost). Adds a route so DynamoDB API
# calls stay on the AWS backbone.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, { Name = "${var.name_prefix}-dynamodb-vpce" })
}

# Interface endpoint for CloudWatch Logs so the function can ship logs without
# any internet egress.
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-logs-vpce" })
}

# Lock down the VPC's default security group: no ingress and no egress. AWS
# creates this group automatically; leaving it permissive is a common finding.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-default-sg-locked" })
}

# VPC flow logs capture all network flows for audit and forensics, written to a
# dedicated (optionally CMK-encrypted) log group.
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/${var.name_prefix}-vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow" {
  name                 = "${var.name_prefix}-vpc-flow-logs-role"
  assume_role_policy   = data.aws_iam_policy_document.flow_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "flow" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow" {
  name   = "${var.name_prefix}-vpc-flow-logs-policy"
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow.arn
  iam_role_arn             = aws_iam_role.flow.arn
  max_aggregation_interval = 600

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc-flow-log" })
}

# Lambda reaches DynamoDB via its GATEWAY endpoint, whose traffic targets the AWS
# service prefix list (not the VPC CIDR). The VPC-CIDR egress rule only covers the
# interface endpoints, so add explicit egress to the DynamoDB prefix list.
resource "aws_vpc_security_group_egress_rule" "lambda_dynamodb" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to DynamoDB via gateway endpoint prefix list"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.dynamodb.prefix_list_id
}
