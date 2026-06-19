# Module: api_gateway

A REST API exposing `GET`/`POST` `/health`, integrated with the Lambda via
`AWS_PROXY`.

- **Throttling**: usage-plan rate/burst limits plus stage method settings
  (DDoS protection), and a per-key daily **quota**.
- **API key authentication**: methods require an API key, tied to a usage plan.
- **Request validation**: a JSON-schema model requires the `payload` key, so
  invalid POST bodies are rejected at the edge before reaching the Lambda.
- **Access logging** to a dedicated, optionally CMK-encrypted log group.

The API key **value** is never exported into Terraform state output; only its
id is returned. Retrieve the value out-of-band with the AWS CLI.

Outputs: `invoke_url`, `rest_api_id`, `api_key_id`.
