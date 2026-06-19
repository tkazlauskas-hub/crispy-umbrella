# ADR 0007: Apply IAM permissions boundaries to all workload roles

## Status
Accepted.

## Context
Least-privilege inline policies define what a role *should* do, but a future
mistake (an over-broad policy edit, a compromised pipeline) could widen a role.
A permissions boundary is a separate ceiling that an inline policy can never
exceed.

## Decision
Bootstrap creates a managed **permissions boundary** policy. Every role the
stack creates (Lambda execution role, VPC flow-log role) attaches it, and the
deploy role is only permitted to **create roles that carry the boundary**
(`iam:PermissionsBoundary` condition on `iam:CreateRole`).

## Consequences
- Even a misconfigured inline policy cannot grant `iam:*`, `organizations:*`, or
  key-administration actions — the boundary denies them.
- The pipeline cannot escalate privilege by minting an unbounded role.
- The boundary must be kept a superset of what workload roles legitimately need
  (logs, DynamoDB, KMS-via-service, ENI, X-Ray).

## Why this matters for a bank
Defence in depth on identity is a core control. Boundaries give a hard,
centrally owned ceiling independent of day-to-day policy changes — exactly the
kind of guardrail auditors and regulators look for.

## Alternatives considered
- **Rely on least-privilege inline policies alone**: simpler, but a single bad
  edit could over-grant. Rejected for a regulated context.
