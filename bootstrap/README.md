# Bootstrap

One-time setup that an administrator runs **before** the main pipeline can work.
It creates everything the CI/CD pipeline needs but cannot create for itself:

1. **Remote state backend** — an encrypted, versioned S3 bucket and a DynamoDB
   lock table.
2. **GitHub OIDC provider** — so GitHub Actions can obtain short-lived AWS
   credentials with no long-lived secrets.
3. **CI deploy role** — assumable only by this repo's `main` branch and the
   `staging`/`production` environments, scoped to the resources this project
   manages.
4. **API Gateway account CloudWatch role** — a per-account/region singleton that
   enables API Gateway logging.
5. **IAM permissions boundary** — the maximum-permissions envelope every workload
   role created by the pipeline must carry.

The state bucket is created with versioning, KMS encryption, a TLS-only policy
and **S3 server access logging** to a dedicated log bucket.

## Usage

```bash
cd bootstrap
terraform init
terraform apply \
  -var="aws_region=eu-central-1" \
  -var="state_bucket_name=homework-health-check-tfstate-<unique-suffix>" \
  -var="github_owner=<your-github-username-or-org>" \
  -var="github_repo=homework-health-check"
```

Then copy the outputs into your GitHub repository settings (see the root
`README.md`, "CI/CD setup"):

| Output            | GitHub setting (Actions variable) |
|-------------------|-----------------------------------|
| `deploy_role_arn` | `AWS_DEPLOY_ROLE_ARN`             |
| `state_bucket`    | `TF_STATE_BUCKET`                 |
| `lock_table`      | `TF_LOCK_TABLE`                   |
| `region`          | `AWS_REGION`                      |
| `permissions_boundary_arn` | `PERMISSIONS_BOUNDARY_ARN`|

> Bootstrap uses **local state** by design — it is the component that creates
> the remote backend. Keep its state file safe, or migrate it into the new
> bucket afterwards with `terraform init -migrate-state`.
