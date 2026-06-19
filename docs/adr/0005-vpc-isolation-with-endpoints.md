# ADR 0005: Run Lambda in a private VPC with VPC endpoints

## Status
Accepted.

## Context
The function only needs to reach two AWS services: DynamoDB and CloudWatch
Logs. Placing a Lambda in a VPC traditionally implies a NAT gateway for egress,
which adds cost and an internet path.

## Decision
Run the Lambda in **private subnets with no NAT and no internet gateway**, and
provide service connectivity with VPC endpoints:
- a **gateway endpoint** for DynamoDB (no hourly cost), and
- an **interface endpoint** for CloudWatch Logs.

The Lambda security group permits no inbound traffic and only HTTPS egress
inside the VPC.

## Consequences
- The function has **no route to the public internet** — a strong containment
  property and a smaller attack surface.
- Traffic to AWS services stays on the AWS network.
- The interface endpoint has a small hourly cost; the DynamoDB gateway endpoint
  is free.
- Adds ENI cold-start considerations; acceptable for this workload.

## Why this matters for a bank
Network isolation and "no public egress" are common control requirements for
workloads that touch customer or transactional data. Keeping service traffic on
private endpoints supports data-residency and exfiltration-prevention controls.

## Alternatives considered
- **Lambda with no VPC**: simplest and avoids ENI overhead, but the task asks
  for VPC isolation and a bank generally prefers private networking for
  data-plane workloads.
- **VPC + NAT gateway**: works, but adds cost and an internet egress path we do
  not need. Rejected in favour of endpoints.
