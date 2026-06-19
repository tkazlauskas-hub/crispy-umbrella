# ADR 0004: Encrypt with a customer-managed KMS key (CMK)

## Status
Accepted.

## Context
The task requires the DynamoDB table to use server-side encryption, and a bonus
asks for a customer-managed KMS key. DynamoDB also supports an AWS-owned key at
no cost.

## Decision
Provision a **customer-managed key** per environment, with **automatic key
rotation** enabled, and use it to encrypt both the DynamoDB table and the
project's CloudWatch log groups ("encryption everywhere").

## Consequences
- We control the key policy, rotation, and lifecycle, and every use of the key
  is recorded in CloudTrail — a clear audit trail.
- The Lambda execution role is granted key usage **only via DynamoDB**
  (`kms:ViaService = dynamodb.<region>.amazonaws.com`), so it cannot use the key
  for anything else.
- Small additional cost per key and per API call versus an AWS-owned key.

## Why this matters for a bank
Customer-managed keys give the institution control and auditability over the
keys protecting its data — typically a hard requirement for regulated data, and
it enables independent key rotation and, if ever needed, revocation.

## Alternatives considered
- **AWS-owned/AWS-managed key**: zero key management, but no control over the
  policy or rotation and a weaker audit story. Rejected for a banking context.
