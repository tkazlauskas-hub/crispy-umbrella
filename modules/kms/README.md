# Module: kms

A customer-managed KMS key (CMK) with automatic rotation. Used to encrypt the
DynamoDB table and the environment's CloudWatch log groups.

The key policy:
- grants the **account root** `kms:*` (AWS-recommended baseline so IAM policies
  can delegate access without risk of lock-out), and
- allows the **CloudWatch Logs service** to use the key, but only for log groups
  named for this environment (`ArnLike` encryption-context condition).

Principals that write to DynamoDB receive their KMS permissions through their
own IAM role (scoped with a `kms:ViaService` condition), not through this key
policy.

Outputs: `key_arn`, `key_id`, `alias_name`.
