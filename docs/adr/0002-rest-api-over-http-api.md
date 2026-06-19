# ADR 0002: Use a REST API (not an HTTP API)

## Status
Accepted.

## Context
API Gateway offers two flavours: HTTP APIs (v2, cheaper, lower latency) and
REST APIs (v1, more features). The task requires throttling, and the bonus
requirements ask for API-key authentication and rejecting invalid requests at
the gateway.

## Decision
Use a **REST API**. It natively supports **API keys + usage plans** (with
per-key throttling and quotas) and **request-body validation** via JSON-schema
models — neither of which HTTP APIs provide natively.

## Consequences
- We get API keys, usage-plan quotas, and edge request validation without
  bolting on a custom Lambda authorizer.
- REST APIs cost marginally more per request and add a little latency versus
  HTTP APIs — negligible for a health-check endpoint.

## Why this matters for a bank
Native, declarative controls (validation, quotas, keys) are easier to audit and
reason about than custom code, and rejecting malformed input at the edge is a
defense-in-depth measure that keeps untrusted data away from compute.

## Alternatives considered
- **HTTP API + Lambda authorizer**: cheaper, but adds custom auth code to
  build, test and secure, and still needs extra work for request validation.
  Rejected: more moving parts for less built-in assurance.
