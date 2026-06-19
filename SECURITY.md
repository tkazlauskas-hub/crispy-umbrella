# Security policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately to the repository owner (or,
in an organisation, via the security mailbox). Do not open a public issue for
security problems. We aim to acknowledge reports within two business days.

## Controls in this repository

- **No long-lived cloud credentials.** CI authenticates to AWS via GitHub OIDC;
  the deploy role's trust policy is pinned to this repository's `main` branch and
  protected environments.
- **Least privilege.** The Lambda execution role and the CI deploy role are
  scoped to specific resource ARNs; the few unavoidable wildcards are documented
  in `docs/security-scanning.md`. All workload roles carry an IAM permissions
  boundary.
- **Encryption everywhere.** DynamoDB and CloudWatch log groups use a
  customer-managed KMS key with rotation; the state bucket is KMS-encrypted.
- **Shift-left scanning.** Trivy (IaC + dependencies + secrets) runs
  on every pull request and again, as a hard gate, before any `terraform apply`.
- **Supply chain.** The Lambda artifact is built in CI with an SBOM and a signed
  build-provenance attestation; third-party Actions are watched by Dependabot.

## Supported versions

The `main` branch is the supported version. Dependencies and pinned Action
versions are kept current via Dependabot.
