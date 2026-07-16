# AWS EKS Reference Platform

A public AWS platform spanning multiple accounts, built entirely in the open. Every architectural decision is documented, every resource is Terraform, and no secret is ever stored in this repository.

## What this is

A forkable reference implementation of an AWS organization hosting a Kubernetes based internal developer platform, demonstrated with a realistic sample workload (a fictional fishing charter booking SaaS). It grows in layers:

| Layer | Scope | Status |
|-------|-------|--------|
| 0 | Org bootstrap: accounts, OUs, SCPs, state backend, GitHub OIDC | 🚧 In progress |
| 1 | Landing zone: identity, logging, security tooling, CI/CD, data pipeline, Bedrock RAG service | Planned |
| 2 | EKS platform: Cilium, mesh, Prometheus/OpenTelemetry, ArgoCD, Kyverno, Backstage | Planned |
| 3 | GPU/AI serving: GPU Operator, MIG, vLLM | Planned |
| 4 | Architecture docs: full ADR log, threat model, FinOps dashboard | Planned |

## Design principles

1. **Zero stored credentials.** GitHub Actions authenticates to AWS via OIDC. Workloads use IAM roles. Humans use IAM Identity Center SSO. There aren't any IAM users or access keys anywhere in this organization.
2. **Everything is code.** The only manual steps are the unavoidable bootstrap that creates the organization, documented honestly in [docs/bootstrap.md](docs/bootstrap.md).
3. **Forkable by design.** Account IDs, domains, and values specific to your org are variables. Fork it, set your values, deploy your own.
4. **Costs stay capped.** Spot capacity, scale to zero, and a documented destroy and rebuild flow. If it can't be rebuilt from this repo, it doesn't belong in this repo.
5. **Decisions are documented.** Every significant choice gets an Architecture Decision Record (ADR), a short note explaining what we decided and why. New to the concept? Start with [docs/adr/](docs/adr/), which explains the format and indexes every decision.

## Account architecture

```
Management (org root: Organizations, Identity Center, billing only)
├── Security OU
│   └── security        (GuardDuty/Security Hub delegated admin, log archive)
├── Infrastructure OU
│   └── shared-services (CI/CD roles, ECR, networking hub)
└── Workloads OU
    ├── workloads-dev
    └── workloads-prod
```

## Getting started

1. Complete the manual bootstrap: [docs/bootstrap.md](docs/bootstrap.md)
2. Deploy the state backend and GitHub OIDC: `terraform/bootstrap/`
3. Deploy the organization: `terraform/org/`

## License

MIT. See [LICENSE](LICENSE).
