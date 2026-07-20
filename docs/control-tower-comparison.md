# What AWS Control Tower Would Have Done For You

This repo builds a landing zone from raw AWS Organizations and Terraform. Most
organizations doing the same job in production use **AWS Control Tower** instead.
This page maps the two against each other, step by step, so you can see exactly
what Control Tower automates, what it does not, and which choice fits your
situation.

The decision itself is recorded in
[ADR-0002](adr/0002-raw-organizations-over-control-tower.md). This page is the
reference detail behind it.

> **This is not an argument against Control Tower.** For a company with a
> deadline, a compliance obligation, or more than a handful of accounts, Control
> Tower is very often the right answer. This repo skips it deliberately, as a
> teaching choice, so the mechanics it normally hides stay visible.
>
> I have done this work on a production AWS migration that used Control Tower, so
> the comparison below is not academic. Everything on this page is sourced from
> public AWS documentation.

## What Control Tower Sets Up

When you launch a landing zone, Control Tower does the following in your
management account, in under an hour:

- Creates a **Security OU** containing two **shared accounts**: **Log Archive**
  (repository for API activity and resource configuration logs from every account)
  and **Audit** (restricted account giving security teams cross-account access).
- Optionally creates a **Sandbox OU**.
- Creates an **IAM Identity Center** directory with preconfigured groups and single
  sign-on, or lets you self-manage your identity provider.
- Applies all **mandatory preventive and detective controls** across the
  organization.
- Provides **Account Factory** for vending new accounts from a standard template,
  a **dashboard**, and **drift detection** to flag divergence from the baseline.

Under the hood it orchestrates AWS Organizations, Service Catalog and IAM Identity
Center, and deploys resources using **CloudFormation StackSets**.

Two details worth knowing before you commit:

- **Preventive controls are not applied to the management account.** This is the
  same limitation raw SCPs have, and the reason this repo keeps workloads out of
  the management account entirely.
- **Shared account names are fixed at launch.** They cannot be renamed later, and
  existing accounts cannot be added for security and logging after the initial
  launch.

## Step By Step Against This Repo

Mapped to the steps in [getting-started.md](getting-started.md):

| This repo's step | Control Tower gives you | You still build it yourself |
|---|---|---|
| **0.** Manual bootstrap (management account, Organizations, Identity Center) | Organizations wiring and an Identity Center directory with groups and SSO, as part of landing zone setup | Creating the management account itself, root hygiene, MFA |
| **1.** `terraform/bootstrap` (state bucket, GitHub OIDC) | nothing | all of it. Control Tower does not manage your IaC backend or your CI identity |
| **2.** `terraform/org` (OUs, accounts, SCPs) | Security OU, Log Archive + Audit accounts, optional Sandbox OU, Account Factory for further accounts, mandatory controls | OUs beyond its structure, and any SCP not in the control catalog |
| **3.** `terraform/budgets` | nothing | all of it |
| **4a.** `identity` | the Identity Center directory and preconfigured groups | your specific permission sets and assignments |
| **4b.** `logging` (org CloudTrail, audit bucket) | the Log Archive account and centralized CloudTrail + Config logging | Object Lock / WORM, retention policy, bucket policy hardening ([ADR-0017](adr/0017-s3-object-lock-audit-trail.md)) |
| **4c.** `config` | AWS Config enabled across enrolled accounts, detective controls | conformance packs, custom rules, the aggregator layout |
| **4d.** `security` (GuardDuty, Security Hub, Access Analyzer) | not part of the landing zone | all of it, including delegated administration |
| **4e.** `cicd` (per-account OIDC deploy roles, ECR) | nothing | all of it |
| **4f.** `networking` (Transit Gateway, VPCs, NAT, flow logs) | nothing | all of it |
| **5.** `eks`, `argocd` (cluster, GitOps, autoscaling, policy, secrets) | nothing | all of it |

### The Takeaway

**Control Tower covers roughly step 0, step 2, and parts of 4a, 4b and 4c.**
Everything else in this repo, the IaC backend and CI identity, budgets, threat
detection, the entire network, the cluster, GitOps delivery, policy enforcement
and secrets, is work you do either way.

That is the point most worth internalizing: Control Tower solves **account
structure, guardrails, centralized logging and identity**. It does not build your
network or your compute platform. If you adopt it expecting "landing zone solved",
you will still be writing most of what is in this repository.

## Trade-Offs, Honestly

**Choosing Control Tower buys you:**

- A working, AWS-supported landing zone in under an hour instead of days.
- A curated **control catalog** (preventive, detective, proactive; mandatory,
  strongly recommended, elective) rather than SCPs you write and test yourself.
- **Drift detection** and a dashboard, so divergence from the baseline is visible.
- **Account Factory**, so teams can vend compliant accounts without you.
- An **upgradeable** landing zone: AWS ships new versions and you update into them.

**Choosing Control Tower costs you:**

- **An opinionated structure.** Its OU layout and shared accounts are its own, and
  the shared account names are permanent from launch.
- **Managed resources you must not touch.** Modifying or deleting Control Tower
  managed resources outside supported methods puts the landing zone into an
  unknown state. If you are used to Terraform owning everything, this is the
  biggest adjustment.
- **A second IaC system.** It runs on CloudFormation StackSets. A Terraform shop
  ends up operating both.
- **Less visibility.** Convenient in production, unhelpful when you are trying to
  learn what a landing zone actually consists of, which is exactly why this repo
  does not use it.

**If you want both**, AWS provides **Account Factory for Terraform (AFT)**: a
Terraform-based, GitOps-style pipeline for provisioning and customizing accounts
while Control Tower governs them. It supports Terraform Community Edition, HCP
Terraform and Terraform Enterprise, with CodeCommit or other sources via
CodeConnections. That is usually the right shape for a Terraform team that also
wants Control Tower's guardrails.

## Which Should You Use?

| Your situation | Recommendation |
|---|---|
| Company migrating to AWS, real deadline, compliance requirements | **Control Tower**, add **AFT** if you are a Terraform shop |
| Many accounts, multiple teams needing to vend their own | **Control Tower** (Account Factory is the point) |
| You need full control of every resource, or one IaC tool only | **Raw Organizations**, the approach in this repo |
| Learning how a landing zone actually works | **Raw Organizations**, then adopt Control Tower knowing what it does |
| Small, static account count, strong Terraform skills | Either. This repo shows the manual path is tractable |

The honest summary: this repo is a **teaching implementation**, not a
recommendation to avoid Control Tower. Read it to understand the mechanics, then
make the call that fits your constraints.

## Sources

- [What is AWS Control Tower?](https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html)
- [How AWS Control Tower works (landing zone structure)](https://docs.aws.amazon.com/controltower/latest/userguide/how-control-tower-works.html)
- [What are the shared accounts?](https://docs.aws.amazon.com/controltower/latest/userguide/what-shared.html)
- [Overview of Account Factory for Terraform (AFT)](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)
