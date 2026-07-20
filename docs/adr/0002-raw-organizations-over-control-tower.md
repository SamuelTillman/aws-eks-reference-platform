# ADR-0002: Raw AWS Organizations + Terraform over Control Tower

**Status:** Accepted · **Date:** 2026-07

> **See also:** [control-tower-comparison.md](../control-tower-comparison.md) maps Control Tower against this repo's deploy steps in detail: what it provisions, what it does not cover, the trade-offs both ways, and AFT as the Terraform bridge.

## Context

AWS offers two mainstream paths to governance across multiple accounts: Control Tower (with Account Factory / AFT) or AWS Organizations managed directly in Terraform. Control Tower is the common enterprise default.

## Decision

This platform manages the organization directly with Terraform: OUs, member accounts, and SCPs as first class resources in `terraform/org/`.

## Rationale

1. **Forkability.** A Control Tower landing zone can't be forked; a Terraform org module can. Anyone can clone this repo, set variables, and reproduce the structure.
2. **Legibility.** Control Tower provisions significant machinery behind the scenes. A reference platform should show what that machinery is, not hide it.
3. **Scale honesty.** Control Tower earns its complexity at enterprise account counts. At five accounts, it's overhead without payoff.
4. **Teaching value.** Understanding raw Organizations, SCP evaluation, and account vending is exactly what Control Tower abstracts away, and exactly what this platform intends to demonstrate.

## Consequences

- There's no Account Factory: account vending is a Terraform resource, not a self service catalog
- Guardrails are SCPs written by hand rather than Control Tower managed controls: fewer, but fully visible
- If the platform ever needed dozens of accounts, this decision would be revisited (and that revisit would be its own ADR)
