# ADR-0001: Why this platform exists

**Status:** Accepted · **Date:** 2026-07

## Context

Tutorials show fragments; real platforms are systems. Most public AWS examples use a single account, serve a single purpose, and quietly depend on stored credentials or prerequisites someone built by hand. There's value in a reference implementation that's honest about its bootstrap, complete in its structure, and reproducible by anyone who forks it.

This repository is a personal build that runs for years and grows one layer at a time. Every layer must meet production standards, stay publicly reviewable, and remain rebuildable from code.

## Decision

Build an AWS organization with multiple accounts hosting a Kubernetes based internal developer platform, in public, under an MIT license, with:

1. **Zero stored credentials.** OIDC federation for CI, IAM roles for workloads, SSO for humans
2. **Everything as code.** Manual steps are limited to the documented bootstrap that creates the organization
3. **Forkability.** All values specific to an org are variables
4. **Cost caps.** Spot capacity, scale to zero, and full destroy and rebuild capability
5. **A realistic demo workload.** A fictional fishing charter booking SaaS, so the platform hosts something with real shape (API, database, queue, frontend, async jobs) rather than hello world

## Consequences

- Public scrutiny forces higher hygiene than a private project would
- Some conveniences (credentials that live forever, hardcoded IDs, ClickOps shortcuts) are permanently off the table, which is the point
- Each layer should be understandable on its own and documented in this ADR log
