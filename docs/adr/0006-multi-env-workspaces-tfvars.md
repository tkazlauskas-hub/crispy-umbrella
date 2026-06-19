# ADR 0006: Multi-environment via workspaces + tfvars

## Status
Accepted.

## Context
The task requires `staging` and `prod` to be deployable from the same code
using a `.tfvars` file (e.g. `terraform apply -var-file="staging.tfvars"`).
State for the two environments must not collide.

## Decision
Use one root configuration with:
- a `.tfvars` file per environment for **values** (`staging.tfvars`,
  `prod.tfvars`), and
- Terraform **workspaces** for **state isolation** (the S3 backend stores each
  workspace's state under a separate key prefix automatically).

The `environment` variable drives the `env-resource-name` naming convention and
is validated to be exactly `staging` or `prod`.

## Consequences
- A single source of truth; environments cannot drift structurally.
- State is isolated, so a `staging` apply can never mutate `prod` resources.
- Operators must select the matching workspace before applying. The CI pipeline
  and the `Makefile` do this automatically to remove that footgun.

## Alternatives considered
- **Directory per environment**: structural drift risk; rejected (see ADR 0001).
- **Separate backends per environment without workspaces**: more backend config
  files to maintain; workspaces achieve the same isolation with less ceremony.
