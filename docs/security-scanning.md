# Security scanning and accepted exceptions

Security scanning runs in two places:

1. **Pull requests / CI (`ci.yml`)** — Trivy IaC misconfiguration scan and a
   Trivy filesystem scan (dependencies + secrets). Advisory and educational for
   reviewers.
2. **Delivery (`deploy.yml`)** — the same scans run **before any
   `terraform apply`**, so insecure infrastructure is never deployed.

## Gating philosophy

We **hard-gate on CRITICAL and HIGH** findings. We do not blanket-disable rules.
Instead, the handful of findings that are either mandated by an AWS API or are a
deliberate, documented engineering trade-off are recorded as **explicit, owned
exceptions** in `.trivyignore`. Anything not on the list fails the build.

This mirrors enterprise practice: a clean signal, with every exception visible,
justified, and reviewable in version control.

## Accepted exceptions and why

### Mandatory IAM wildcards
The task forbids wildcards "except where mandatory". Two cases are genuinely
mandatory:

- **EC2 ENI management** for a VPC-attached Lambda
  (`ec2:CreateNetworkInterface`, `DescribeNetworkInterfaces`,
  `DeleteNetworkInterface`, …). These EC2 actions do not support resource-level
  permissions, so `Resource = "*"` is required by the API, not by us.
- **KMS key policies** use `Resource = "*"` by design — the policy is attached
  to the key, so the key *is* the resource. The root-account `kms:*` statement
  is the AWS-recommended baseline that prevents key lock-out and lets IAM
  delegate access. Principals receive narrowly scoped KMS access through their
  own roles (e.g. the Lambda role, restricted with `kms:ViaService`).

Everywhere else, IAM resources are scoped to specific ARNs via the
`env-resource-name` convention, and `iam:PassRole` is constrained to the Lambda
service only.

### Deliberate trade-offs
- **No Lambda DLQ**: the function is invoked **synchronously** by API Gateway,
  where a DLQ does not apply (the caller receives the error directly).
- **No API Gateway caching**: `/health` writes to DynamoDB on every call, so
  responses must never be served from a cache.
- **Lambda env vars not CMK-encrypted**: the only variables are `TABLE_NAME`
  and `LOG_LEVEL` — non-secret. Keeping them on the default key means the
  execution role's KMS access stays strictly `ViaService dynamodb`.
- **No code signing**: out of scope for this exercise.

### State-backend bucket
S3 access logging, cross-region replication and event notifications are not
configured for the Terraform **state** bucket. It is private, versioned,
KMS-encrypted, and TLS-only. Those additional controls add buckets/replication
roles that are out of scope here.

### Cross-module false positive
`CKV2_AWS_5` reports the Lambda security group as "unattached". It is attached
to the function via the `lambda` module's `vpc_config`; the static analyser
cannot follow the value across the module boundary.

### Deliberately omitted (2026)
X-Ray tracing is intentionally not enabled: the AWS X-Ray SDK entered
maintenance mode in 2026 and the modern path is OpenTelemetry / Lambda
Powertools. WAF logging is enabled. The `AWSManagedRulesKnownBadInputsRuleSet`
covers Log4j (`Log4JRCE`).


### Permissions boundaries
All workload roles carry an IAM permissions boundary, and the deploy role may
only create roles that include it — a hard ceiling against privilege escalation.

### Deploy-role read permissions (terraform plan refresh)
On every `terraform plan` the CI deploy role must *read* each managed resource. A few of these reads are account- or region-level APIs that do not support resource-level scoping, so they use `Resource = "*"` (bounded to the deployment region where the API allows it):

- `logs:DescribeResourcePolicies` / `PutResourcePolicy` / `DeleteResourcePolicy` - the WAF log destination is an account-level CloudWatch Logs resource policy.
- `ec2:DescribeVpcAttribute` - reading `enableDnsHostnames` is not resource-scopable.
- `wafv2:GetLoggingConfiguration` / `PutLoggingConfiguration` / `DeleteLoggingConfiguration` - WAF logging lifecycle, bounded to the region.

Lambda attribute reads (`lambda:Get*` / `lambda:List*`) are scoped to the project function ARNs (`*-health-check-*`), not account-wide. These are the minimal additions that let the pipeline run `plan`/`apply` under the scoped role instead of an administrator; all mutating power stays bounded by region and by the permissions boundary.
