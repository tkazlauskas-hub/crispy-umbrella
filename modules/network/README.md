# Module: network

A private-only VPC for the Lambda function.

- Private subnets across multiple AZs, no internet/NAT gateway.
- A least-privilege Lambda security group (no inbound, HTTPS egress only).
- A **DynamoDB gateway endpoint** (free) and a **CloudWatch Logs interface
  endpoint** so the function reaches those services privately.

| Input | Description |
|-------|-------------|
| `name_prefix` | Environment prefix (e.g. `staging`) |
| `vpc_cidr` | VPC CIDR block |
| `private_subnet_cidrs` | One CIDR per AZ |
| `availability_zones` | AZ names |
| `aws_region` | Region for endpoint service names |

Outputs: `vpc_id`, `private_subnet_ids`, `lambda_security_group_id`.
