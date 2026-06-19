# Module: lambda

Packages the source directory, deploys the function into private subnets, and
attaches a least-privilege execution role.

Highlights:
- **Packaging + versioning** via `archive_file` and `publish = true` (a new
  immutable version is published whenever the source hash changes).
- **VPC config**: the function runs in the private subnets and SG from the
  network module.
- **Least-privilege role**: write to its own log stream, `PutItem` to the one
  table, use the CMK only via DynamoDB. The only wildcard is the EC2 ENI block,
  which the EC2 API does not allow to be resource-scoped.
- **Reserved concurrency** caps blast radius and cost.
- A dedicated **log group** with retention and optional CMK encryption.

Outputs: `function_name`, `function_arn`, `invoke_arn`, `version`, `role_arn`.
