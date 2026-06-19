# Module: dynamodb

The request-storage table.

- On-demand (`PAY_PER_REQUEST`) billing — no capacity planning.
- Server-side encryption with a **customer-managed KMS key**.
- **Point-in-time recovery** enabled.
- **TTL** on the `ttl` attribute to auto-expire old records (data minimisation
  and cost control).
- Optional **deletion protection** (enabled for prod via tfvars).

Outputs: `table_name`, `table_arn`.
