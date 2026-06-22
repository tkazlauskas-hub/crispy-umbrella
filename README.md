# Serverless Health Check API

A `/health` endpoint on AWS, defined entirely in Terraform and delivered by a
GitHub Actions CI/CD pipeline for two environments (`staging`, `prod`). Each
request is authenticated and throttled at the edge, validated, then handled by a
Lambda that logs it to CloudWatch, stores it in DynamoDB, and returns a JSON
status.

```
client ─HTTPS + x-api-key─► WAF ─► API Gateway (REST) ─AWS_PROXY─► Lambda (private VPC) ─► DynamoDB
                            rate    throttle · validate body        validate · log · save    SSE (CMK)
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/adr/`](docs/adr/)
for the design and the rationale behind each decision.

## Repository structure

```
.
├── bootstrap/            One-time: state backend, OIDC, deploy role, permissions boundary
├── modules/
│   ├── network/          Private VPC, endpoints, flow logs, locked default SG
│   ├── kms/              Customer-managed encryption key (rotation)
│   ├── dynamodb/         Request table (SSE-CMK, PITR, TTL)
│   ├── lambda/           Packaging, VPC config, least-privilege IAM
│   └── api_gateway/      REST API: throttling, API key, request validation, WAF
├── lambda/app.py         Lambda source (Python 3.13, boto3 only)
├── tests/                Unit tests (pytest + moto)
├── *.tf                  Root wiring the modules together
├── staging.tfvars / prod.tfvars
└── .github/workflows/    ci.yml (checks) and deploy.yml (delivery)
```

## Prerequisites

- An AWS account and permissions to run the one-time `bootstrap/`.
- Terraform >= 1.9 and the AWS CLI configured locally.
- GitHub repository **Actions variables** (all non-secret; from bootstrap output):

  | Variable | Source |
  |----------|--------|
  | `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arn` |
  | `AWS_REGION` | `region` |
  | `TF_STATE_BUCKET` | `state_bucket` |
  | `TF_LOCK_TABLE` | `lock_table` |
  | `PERMISSIONS_BOUNDARY_ARN` | `permissions_boundary_arn` |

  > Thanks to OIDC there are **no long-lived AWS secrets** in GitHub.

## One-time bootstrap

Creates the remote state backend (encrypted, versioned S3 + DynamoDB lock), the
GitHub OIDC provider, the scoped deploy role, and the IAM permissions boundary
every workload role must carry.

```bash
cd bootstrap
terraform init
terraform apply \
  -var="aws_region=eu-central-1" \
  -var="state_bucket_name=health-check-tfstate-<unique-suffix>" \
  -var="github_owner=<your-user-or-org>" \
  -var="github_repo=<repo-name>"
terraform output     # copy values into the GitHub Actions variables above
```

Then create GitHub **Environments**: `staging` (no protection) and `prod` (add
**Required reviewers** — this is the production approval gate).

## Environments

One root configuration serves both environments. Values live in
`staging.tfvars` / `prod.tfvars`; state is isolated per environment with
Terraform **workspaces**. The `environment` variable drives the
`env-resource-name` convention (e.g. `staging-requests-db`,
`prod-health-check-function`).

## How the CI/CD pipeline works

**`ci.yml`** (pull requests + pushes, no AWS credentials): `terraform fmt`/
`validate` (root + bootstrap), `tflint`, `pytest` unit tests, a **Trivy** IaC
scan and a **Trivy** dependency/secret scan.

**`deploy.yml`** (push to `main` / manual dispatch):

1. **`security`** — Trivy IaC + dependency scans run **before any apply**.
2. **`package`** — builds the Lambda zip, a CycloneDX **SBOM**, and a signed
   **build-provenance** attestation, and uploads the artifact.
3. **`deploy-staging`** — assumes the deploy role via **OIDC**, selects the
   `staging` workspace, plans and applies `staging.tfvars`. Automatic.
4. **`deploy-prod`** — after staging, waits for the `prod` environment's
   required reviewers, then applies `prod.tfvars`.

## Deploy staging — step by step

Push to `main` and the pipeline deploys staging automatically. To do it yourself:

```bash
export TF_STATE_BUCKET=<bucket> TF_LOCK_TABLE=<table> AWS_REGION=eu-central-1
export TF_VAR_permissions_boundary_arn=<permissions_boundary_arn from bootstrap>
make plan  ENV=staging
make apply ENV=staging
terraform output health_endpoint
```

## Test the endpoint

```bash
API_KEY_ID=$(terraform output -raw api_key_id)
API_KEY=$(aws apigateway get-api-key --api-key "$API_KEY_ID" --include-value \
  --query value --output text)
URL=$(terraform output -raw health_endpoint)

# 200 OK
curl -s -X POST "$URL" -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" -d '{"payload": {"check": "ok"}}'
# {"status": "healthy", "message": "Request processed and saved."}

# 400 — missing payload (rejected at the gateway and re-checked in the Lambda)
curl -s -X POST "$URL" -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" -d '{"foo": "bar"}'

# 403 — no API key
```

## Local development

```bash
pip install -r tests/requirements.txt && pytest -q
pip install pre-commit && pre-commit install   # mirrors CI locally
terraform fmt -recursive
```

## Design decisions (ADRs)

- **0001** Reusable Terraform modules.
- **0002** REST API over HTTP API (native API keys + request validation).
- **0003** GitHub OIDC instead of static AWS keys.
- **0004** Customer-managed KMS key with rotation.
- **0005** Private VPC with endpoints, no NAT / no internet egress.
- **0006** Multi-environment via workspaces + tfvars.
- **0007** IAM permissions boundaries on all workload roles.

## How the requirements are met

| Requirement | Where |
|-------------|-------|
| IaC in Terraform | whole repo |
| DynamoDB SSE / customer-managed key | `modules/dynamodb` + `modules/kms` |
| Multi-env (staging/prod) via tfvars | `staging.tfvars`/`prod.tfvars` + workspaces |
| Naming `env-resource-name` | `locals.tf` |
| DynamoDB / API GW / Lambda / IAM | the modules |
| API GW GET+POST, throttling | REST API + usage plan + method settings + WAF rate limit |
| Lambda: log + save(uuid) + 200 JSON | `lambda/app.py` |
| Least-privilege Lambda role + deploy role | `modules/lambda` + `bootstrap` |
| IaC scan before apply | `deploy.yml` `security` job |
| No wildcards (except mandatory) | scoped by ARN; mandatory `*` documented in `docs/security-scanning.md` |
| Input validation (`payload` → 400) | Lambda + API Gateway request model |
| Dependency scanning for the Lambda | Trivy `fs` (vuln + secret) |
| Bonus: modules / packaging+versioning / prod approval | modules; `archive_file`+`publish`+SBOM; `prod` environment gate |
| Bonus: CMK / Lambda in VPC / request validation / API key | KMS module / network + `vpc_config` / request model / API key + usage plan |
| Extra (bank-grade): permissions boundary, WAF, VPC flow logs, supply-chain attestation | bootstrap / api_gateway / network / deploy.yml |

## Assumptions

- The body must be a JSON object containing a `payload` key (per the validation
  requirement); the example client uses POST. A GET without a body returns 400
  by that rule.
- The reviewer runs `bootstrap/` once with administrative credentials; the
  pipeline uses only the scoped deploy role.
- `eu-central-1` is the default region; override via tfvars.

## Notes for the reviewer

- **Provider lock file:** run `terraform init` once and commit the generated
  `.terraform.lock.hcl` (kept out of `.gitignore` on purpose) to pin exact
  provider hashes.
- **First apply:** `bootstrap/` must be applied once before the pipeline runs.
  The `aws_api_gateway_account` CloudWatch role it creates is an account/region
  singleton; on a shared account, reconcile it with any existing setting.
- **WAF logging** can be disabled with `enable_waf_logging = false` if a given
  account needs the CloudWatch log-delivery setup adjusted.

## Cost and teardown

Everything is serverless/on-demand. Standing costs: the CloudWatch Logs
interface endpoint, KMS keys, and WAF. Tear down with `make destroy ENV=staging`
(and `prod`), then `cd bootstrap && terraform destroy`.
