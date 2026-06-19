# ADR 0001: Structure Terraform into reusable modules

## Status
Accepted.

## Context
The infrastructure has clearly separable concerns (network, encryption, data,
compute, edge). A single flat configuration would grow large, mix concerns,
and make multi-environment reuse copy-paste heavy.

## Decision
Split the configuration into focused modules (`network`, `kms`, `dynamodb`,
`lambda`, `api_gateway`) consumed by a thin root module. The root module wires
the modules together and injects environment-specific values.

## Consequences
- Each module has a single responsibility and its own README, variables and
  outputs, which makes it independently reviewable and testable.
- Environments differ only by input values, not by duplicated resource blocks.
- Slightly more boilerplate (variables/outputs per module) — an acceptable cost
  for clarity and reuse.

## Alternatives considered
- **Flat root configuration**: simpler initially, but poor separation of
  concerns and hard to reuse across environments.
- **Separate directory per environment**: duplicates resource definitions and
  invites drift between staging and prod.
