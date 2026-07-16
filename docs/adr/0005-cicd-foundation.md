# ADR-0005: CI/CD foundation (shared-services)

**Status:** Accepted · **Date:** 2026-07

## Context

Layer 0 gave GitHub Actions OIDC access to the **management** account (for
org/state Terraform). To build and deploy actual workloads, CI needs to reach
the **workload** accounts and a container registry, still with zero stored
credentials. This ADR defines that CI/CD foundation. It is the first of the
deferred Layer 1 workstreams from [ADR-0004](0004-layer-1-landing-zone-architecture.md).

Deployment target accounts: `shared-services` (CI hub + registry),
`workloads-dev`, `workloads-prod`.

## Decisions

### 1. Per-account, OIDC-federated deploy roles, no central hub role

Each deployment-target account gets its **own** GitHub OIDC provider and a
`github-actions-deploy` role that the workflow assumes **directly** with a
short-lived token. We do **not** build a single hub role in `shared-services`
that chains into the others.

- No long-lived, broadly-trusted cross-account role to protect.
- Each deploy uses a token scoped to exactly one account + one trust condition.
- Mirrors the Layer 0 management OIDC role, extended per account.

### 2. Trust is scoped per environment, tightly

The OIDC trust condition (`token.actions.githubusercontent.com:sub`) is scoped
per account so a workflow can only assume the role it's entitled to:

| Account | Trust `sub` | Rationale |
|---|---|---|
| `shared-services` | `repo:ORG/REPO:ref:refs/heads/main` | registry pushes happen from main |
| `workloads-dev` | `repo:ORG/REPO:ref:refs/heads/main` | dev deploys from main |
| `workloads-prod` | `repo:ORG/REPO:environment:prod` | prod deploys require a GitHub **Environment** (approval gate) |

The `prod` GitHub Environment (with required-reviewer protection) is created in
the repo so prod deploys can't run without a human approval, the CI equivalent
of our plan/approve discipline.

### 3. Central ECR in `shared-services`

One container registry in `shared-services`, with repository policies granting
**cross-account pull** to the workload accounts (and later, EKS node roles). Each
repo gets a **lifecycle policy** expiring untagged/old images (cost control).
Repositories are variable-driven (`ecr_repositories`), defaulting to the demo
workload's services.

Rationale: one registry to build/scan/sign into, pulled by many accounts, the
standard pattern, and cheaper/simpler than per-account registries.

### 4. Deploy-role permissions: broad now, secured by trust; narrowed in Layer 2

The deploy roles carry a broad managed policy (`AdministratorAccess`) for now,
provisioning EKS, IAM (IRSA), networking, etc. needs wide permissions, and the
exact set isn't known until Layer 2. Security at this stage comes from the
**tight OIDC trust** (only this repo, only the right branch/environment) and
**short-lived sessions**, not from permission breadth. The breadth is a
variable (`deploy_role_policy_arn`) and narrowing to least-privilege per
workload is an explicit Layer 2 task. This matches the Layer 0 management role's
posture (and its documented narrowing path).

### 5. New stack `terraform/cicd`, cross-account via provider aliases

A new stack (`state key cicd/terraform.tfstate`) runs as management and assumes
into `shared-services`, `workloads-dev`, `workloads-prod` via provider aliases
(same pattern as `logging`/`config`, account IDs from `org` remote state). A
reusable `modules/github-oidc-role` (OIDC provider + role + policy attachment)
is instantiated per account to stay DRY.

## Consequences

- CI can build/push to ECR and deploy into each workload account with no stored
  credentials, OIDC tokens only.
- Prod deploys are gated behind a GitHub Environment approval, giving a
  human checkpoint without a human credential.
- The broad deploy-role permissions are the main thing to revisit in Layer 2;
  tracked as a follow-up, same as the Layer 0 OIDC role.
- The `prod` GitHub Environment and its protection rules are repo config (not
  Terraform). Reproduce with `gh` (replace the reviewer id with your GitHub user
  id from `gh api user --jq .id`):

  ```bash
  gh api --method PUT repos/<ORG>/<REPO>/environments/prod \
    --input - <<'JSON'
  { "wait_timer": 0, "reviewers": [{ "type": "User", "id": <YOUR_GH_USER_ID> }],
    "deployment_branch_policy": null }
  JSON
  ```

  A prod-targeting workflow must declare `environment: prod`; GitHub then blocks
  the run pending a reviewer's approval before the OIDC token is issued.
- Deferred Layer 1 workstreams still pending: networking (ADR-0006?), data
  pipeline, Bedrock RAG.
