# ADR 0003: Authenticate CI with GitHub OIDC, not static keys

## Status
Accepted.

## Context
The pipeline must deploy to AWS. The two common options are (a) storing a
long-lived IAM user access key/secret in GitHub secrets, or (b) federating
GitHub's OIDC identity provider with AWS IAM to mint short-lived credentials.

## Decision
Use **GitHub OIDC**. Bootstrap registers
`token.actions.githubusercontent.com` as an IAM OIDC provider and creates a
deploy role whose trust policy only allows this repository's `main` branch and
the `staging`/`production` GitHub Environments to assume it.

## Consequences
- **No long-lived AWS secrets** live in GitHub — nothing to leak or rotate.
- Credentials are short-lived (max 1 hour) and automatically scoped per job.
- The trust policy pins `aud = sts.amazonaws.com` and an explicit `sub` list,
  so a fork or an unrelated branch cannot obtain credentials.
- Requires a one-time bootstrap with elevated credentials.

## Why this matters for a bank
For a regulated financial institution (think DORA, ISO 27001), eliminating
standing credentials is a major reduction in attack surface and a clean audit
story: every deployment is traceable to a specific repo, branch/environment and
workflow run, with no shared secret to manage.

## Alternatives considered
- **Static IAM user keys in GitHub secrets**: simplest, but introduces a
  long-lived, high-value secret and rotation burden. Rejected.
