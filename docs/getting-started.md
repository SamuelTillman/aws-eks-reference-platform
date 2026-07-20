# Getting Started: Fork To Running Platform

This is the deploy-it-yourself guide. Follow it top to bottom and you end up with
a working multi-account AWS platform running EKS, then tear it back down to
almost nothing.

## What You Are Actually Building (And Why It Looks Like This)

This is a **landing zone**: the account structure, guardrails, audit trail, and
network backbone an organization stands up *before* the first workload runs. It
is the same class of work a cloud or SRE team does during a real migration to AWS,
and the order below is roughly the order a real migration follows: get the
organization and audit trail right first, then network, then compute, then
delivery. I have done this on a production migration; the sequencing here reflects
that, not a tutorial's convenience.

**Most teams doing this in production use [AWS Control Tower](https://aws.amazon.com/controltower/),**
which automates a lot of it: it vends accounts, applies guardrails, sets up the
log archive and audit accounts, and gives you a dashboard. This repo deliberately
does **not** use Control Tower. It builds the same outcomes from raw AWS
Organizations and Terraform, because the point is to *see the mechanics* that
Control Tower hides: why the log archive lives in its own account, what a guardrail
actually is (a Service Control Policy), how delegated administration works, why
the audit bucket is write-once.

The reasoning behind that choice, and what you give up, is in
[ADR-0002](adr/0002-raw-organizations-over-control-tower.md). For a step-by-step
mapping of **which of the steps below Control Tower would have done for you**, and
which you would build either way, see
**[control-tower-comparison.md](control-tower-comparison.md)**. Short version: it
covers account structure, guardrails, centralized logging and identity. The
network, the cluster, and delivery are yours regardless.

If you are doing this for a real company on a deadline, Control Tower is very often
the right answer. Read this repo to understand what it is doing for you.

Every significant decision here has an [ADR](adr/). When you wonder "why is it
built this way", that is where the answer lives.

## Before You Start

### Cost, stated plainly

| State | Cost | Notes |
|---|---|---|
| Layer 0 + 1 only (governance, audit, network) | **~$15-40/month** | usage-based; AWS Config is the largest variable |
| Plus the EKS cluster running | **~$260-285/month** | Cluster, Transit Gateway, NAT, spot nodes |
| Torn down (compute destroyed) | **back to ~$15-40/month** | Audit trail is kept on purpose |

These are **estimates from public AWS list pricing** (us-east-1, 730 hrs/month),
not measured from a bill. Derivation for the running figure:

| Line | Calculation | Monthly |
|---|---|---|
| Transit Gateway | 3 VPC attachments x $0.05/hr | $109.50 |
| EKS control plane | $0.10/hr | $73.00 |
| EC2 spot, 2 x t3.large | ~$0.025/hr each, spot varies | ~$36.50 |
| NAT Gateway (single) | $0.045/hr | $32.85 |
| EBS gp3, 100 GB | $0.08/GB-month | $8.00 |

Data processing and egress are usage-dependent and excluded. **Note that Transit
Gateway, not the cluster, is the largest single line item.** Most people assume
the opposite. The prod VPC is attached but runs no workloads, so detaching it
until you need it saves ~$36.50/month on its own.

> **The $0.10/hr control plane rate applies to a Kubernetes version in
> *standard* support. An end-of-life version costs $0.60/hr, six times as much,
> or roughly $438/month instead of $73.** This is why `cluster_version` matters
> and why the example pins a current minor.

The compute tier is designed to be destroyed and rebuilt on demand
([ADR-0008](adr/0008-cicd-lifecycle-teardown-rebuild.md)). **Deploy the budgets
stack early** (step 3) so you get alerted before a surprise.

> **The one irreversible step:** enabling S3 Object Lock on the audit bucket
> (step 6, optional) can never be undone, and locked objects cannot be deleted
> until retention expires. Set `enable_log_object_lock = false` if you are just
> kicking the tyres. See [ADR-0017](adr/0017-s3-object-lock-audit-trail.md).

### You need

- **A fresh AWS account** to be the organization management account, with a
  payment method. Do not reuse an account that already has workloads in it.
- **An email address you control that supports `+` aliasing** (Gmail, Google
  Workspace, Fastmail...). Each member account needs a unique root email;
  `you+security@example.com` style aliases are how that works without inventing
  five mailboxes. Verify aliasing works *before* you start, see
  [bootstrap.md](bootstrap.md) step 5.
- **Tools:**

  | Tool | Version | Why |
  |---|---|---|
  | Terraform | **>= 1.10** (CI pins `1.12.2`) | needs S3 native state locking (`use_lockfile`) |
  | AWS CLI | **v2** | SSO login |
  | `kubectl` | matching EKS 1.35 (±1 minor) | reach the cluster |
  | `git`, a GitHub account | | to fork |
  | `helm` | optional | inspecting charts |
  | `gh` CLI | optional | triggering the teardown/rebuild button |

- **Roughly 60-90 minutes** for a first full deploy, most of it waiting on AWS.

### Decide your values

You will replace these throughout. Pick them now:

| Value | Example | Appears in |
|---|---|---|
| `name_prefix` | `refplatform` | every stack; prefixes all resource names |
| `aws_region` | `us-east-1` | every stack |
| Root email pattern | `you+{account}@example.com` | `terraform/org` |
| `github_org` / `github_repo` | your fork | `bootstrap`, `cicd` |
| Your public IP | `203.0.113.10/32` | `eks` (API allowlist) |

## Step 0: Manual Bootstrap (~20 min, one time)

Some things cannot be Terraformed because they create the very thing Terraform
would authenticate to. Follow **[bootstrap.md](bootstrap.md)** exactly. It covers:
creating the management account, locking down root (MFA, no access keys), enabling
Organizations, enabling IAM Identity Center, and verifying email aliasing.

**Verify before continuing:** `aws sts get-caller-identity` returns your
management account, and you can sign in through the Identity Center portal.

## Step 1: `terraform/bootstrap` (~3 min)

Creates the **Terraform state bucket** and the **GitHub Actions OIDC role**. This
is the only stack that starts with local state and then migrates into S3.

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_org / github_repo
AWS_PROFILE=<your-sso-profile> terraform init
AWS_PROFILE=<your-sso-profile> terraform plan -out=bootstrap.tfplan
AWS_PROFILE=<your-sso-profile> terraform apply bootstrap.tfplan
```

Then take the bucket name from `terraform output`, put it in `backend.hcl`
(gitignored, it contains your account ID), and re-init to move state into S3:

```bash
cp backend.hcl.example backend.hcl             # set bucket = the output above
AWS_PROFILE=<your-sso-profile> terraform init -backend-config=backend.hcl -migrate-state
```

**Verify:** the bucket exists and `terraform state list` still shows your
resources after the migration.

> **If your GitHub OIDC role fails to assume later**, your account emits
> immutable-ID subjects. Set `github_owner_id` / `github_repo_id`. This is
> [layer2-issues #2](layer2-issues.md), and it is the single most common
> fork-time snag.

## Step 2: `terraform/org` (~5 min)

Creates the **OUs, the four member accounts, and the guardrail SCPs**.

```bash
cd ../org
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
AWS_PROFILE=<profile> terraform init -backend-config=backend.hcl
AWS_PROFILE=<profile> terraform plan -out=org.tfplan    # READ THIS ONE CAREFULLY
AWS_PROFILE=<profile> terraform apply org.tfplan
```

**Account creation is not instant** and is not easily reversible: closing AWS
accounts is a manual, rate-limited process. Read the plan properly here.

**Verify:** `aws organizations list-accounts` shows five accounts, and each SCP is
attached to its OU.

From here on, every stack reads account IDs out of this stack's remote state, so
**no account ID is ever written into a tracked file.**

## Step 3: `terraform/budgets` (~2 min), Do This Early

Cost alerts at `$50` increments. Deploy it before the expensive layers, not after.

```bash
cd ../budgets
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars  # set alert_email
AWS_PROFILE=<profile> terraform init -backend-config=backend.hcl
AWS_PROFILE=<profile> terraform apply
```

## Step 4: Layer 1, The Landing Zone (~25 min total)

These give you identity, an audit trail, compliance monitoring, threat detection,
CI/CD identity, and the network. Deploy in this order (`logging` before `config`
and `security`, because they all deliver into the audit account):

| # | Stack | Creates | ~Time |
|---|---|---|---|
| 4a | `identity` | Identity Center permission sets, groups, assignments | 3 min |
| 4b | `logging` | Org CloudTrail + write-isolated audit bucket (KMS) | 5 min |
| 4c | `config` | Config recorders in all accounts + aggregator + conformance pack | 10 min |
| 4d | `security` | GuardDuty, Security Hub, Access Analyzer (delegated to `security`) | 5 min |
| 4e | `cicd` | Per-account OIDC deploy roles + central ECR | 3 min |
| 4f | `networking` | Transit Gateway hub, 3 VPCs, single NAT, flow logs | 5 min |

Each follows the same pattern:

```bash
cd ../<stack>
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
AWS_PROFILE=<profile> terraform init -backend-config=backend.hcl
AWS_PROFILE=<profile> terraform plan -out=<stack>.tfplan
AWS_PROFILE=<profile> terraform apply <stack>.tfplan
```

> **Expect one or two failures here, and do not panic.** Org-wide AWS services
> need *trusted service access* and *delegated administration* enabled explicitly,
> and Terraform does not always do it for you. Every failure we hit, with the exact
> error and fix, is in **[layer1-issues.md](layer1-issues.md)**. Read it if a stack
> errors, the answer is very likely already there.
>
> Cheapest general fix: `aws organizations enable-aws-service-access
> --service-principal <svc>.amazonaws.com`, then re-apply.

**Verify:** CloudTrail is logging to the audit bucket; Config shows recorders
`recording=true` in all five accounts; GuardDuty and Security Hub show `security`
as delegated admin.

## Step 5: Layer 2, The Cluster (~20 min)

```bash
cd ../eks
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
```

Set in `terraform.tfvars`:
- `public_access_cidrs = ["<your-public-ip>/32"]`, **your** IP, never `0.0.0.0/0`
  (a validation rule rejects it)
- `cluster_admin_principal_arns`, your Identity Center admin role ARN, so you can
  `kubectl` in
- keep `cluster_version` on a **standard-support** minor

```bash
AWS_PROFILE=<profile> terraform init -backend-config=backend.hcl
AWS_PROFILE=<profile> terraform plan -out=eks.tfplan
AWS_PROFILE=<profile> terraform apply eks.tfplan     # ~15 min, control plane is slow
```

Then ArgoCD, which delivers everything else by GitOps:

```bash
cd ../argocd
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
AWS_PROFILE=<profile> terraform init -backend-config=backend.hcl
AWS_PROFILE=<profile> terraform apply
```

**Reaching the cluster** (note the missing `--role-arn`, that form hangs, see
[layer2-issues #4](layer2-issues.md)):

```bash
DEV=$(aws organizations list-accounts --query "Accounts[?Name=='workloads-dev'].Id | [0]" --output text)
creds=$(aws sts assume-role --role-arn "arn:aws:iam::$DEV:role/OrganizationAccountAccessRole" \
  --role-session-name kubectl --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
export AWS_ACCESS_KEY_ID=$(echo "$creds"|cut -f1) \
       AWS_SECRET_ACCESS_KEY=$(echo "$creds"|cut -f2) \
       AWS_SESSION_TOKEN=$(echo "$creds"|cut -f3)
aws eks update-kubeconfig --name <name_prefix>-dev --region <region>
kubectl get nodes
```

**Verify:** nodes are `Ready`, and `kubectl -n argocd get applications` shows
Karpenter, observability, Kyverno and External Secrets syncing. Give them a couple
of minutes; the first status you see is usually mid-install
([layer2-issues #7](layer2-issues.md)).

**Dashboards have no passwords by design** ([ADR-0015](adr/0015-dashboard-access-no-second-credential.md)):

```bash
argocd admin dashboard -n argocd     # ArgoCD, authenticated by your kubeconfig
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# then http://localhost:3000  (plain http, no login: anonymous read-only)
```

## Step 6: Optional Hardening

- **S3 Object Lock** on the audit trail
  ([ADR-0017](adr/0017-s3-object-lock-audit-trail.md)), **irreversible**, read it
  first.
- **Permission boundaries** on every privileged role
  ([ADR-0012](adr/0012-permission-boundaries.md)), already on by default.

## Step 7: Wire Up The Teardown Button (~5 min)

So you can destroy and rebuild from GitHub Actions without local credentials.

In your fork, under **Settings → Secrets and variables → Actions**, add these as
**secrets** (not variables, they embed your account ID and GitHub masks secrets in
public logs):

| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | the OIDC role ARN from step 1 |
| `TF_STATE_BUCKET` | your state bucket name |
| `EKS_PUBLIC_ACCESS_CIDRS` | `["<your-ip>/32"]` |
| `EKS_ADMIN_PRINCIPAL_ARNS` | `["<your admin role ARN>"]` |

Then create a **GitHub Environment** named `platform-lifecycle`
(Settings → Environments) and add yourself as a required reviewer, so a destroy
needs an approval click.

**Verify:** Actions → *Platform Lifecycle* → Run workflow → `stack=networking`,
`action=apply`. It should be a no-op apply that succeeds.

## Step 8: Tear It Down

**Do this when you stop using it.** Full runbook:
[teardown-rebuild.md](teardown-rebuild.md).

Order matters (dependencies): **argocd → eks → networking**.

```bash
gh workflow run platform-lifecycle.yml -f stack=argocd     -f action=destroy -f confirm=argocd
gh workflow run platform-lifecycle.yml -f stack=eks        -f action=destroy -f confirm=eks
gh workflow run platform-lifecycle.yml -f stack=networking -f action=destroy -f confirm=networking
```

> If Karpenter has provisioned nodes, delete the NodePool first so it drains them.
> Those EC2 instances are **not** Terraform-managed and would be orphaned. See
> teardown-rebuild.md step 0.

**Verify you are actually at zero:**

```bash
aws eks list-clusters --region <region>                      # 0
aws ec2 describe-nat-gateways --region <region> \
  --filter Name=state,Values=available --query 'length(NatGateways)'   # 0
aws ec2 describe-transit-gateways --region <region> \
  --query 'length(TransitGateways[?State!=`deleted`])'       # 0
```

Layer 0 and Layer 1 stay up. That is deliberate: the audit trail should outlive
the compute.

## When Something Breaks

Check the issue log for that layer **first**. These are real failures we hit, with
the actual error text, root cause, and fix:

- **[layer0-issues.md](layer0-issues.md)**: bootstrap and org
- **[layer1-issues.md](layer1-issues.md)**: landing zone (the most common snags:
  org service enablement, delegated admin, propagation races)
- **[layer2-issues.md](layer2-issues.md)**: cluster, CI/CD, GitOps

Two traps that cost the most time, worth knowing up front:

1. **Always pass `--region`** to AWS CLI commands. A region-less call falls back to
   your shell default, the region-allowlist SCP denies it, and the error looks like
   a broken IAM policy rather than a missing flag.
2. **CI (`main`), not your local working tree, is the source of truth.** If it works
   locally but not in CI, diff `git show HEAD:<file>` against your local copy before
   blaming Terraform.

## Making It Yours

- Change `name_prefix` and it renames everything consistently.
- Region: change `aws_region` and the `allowed_regions` SCP together, or the
  guardrail will deny your own deploys.
- Fewer accounts: possible, but the isolation between "where workloads run" and
  "where the audit trail lives" is the point. Collapse it knowingly.
- Not everything here is required. `security` (GuardDuty, Security Hub) and the
  Config conformance pack sit behind `enable_*` flags precisely so you can run a
  cheaper version.
