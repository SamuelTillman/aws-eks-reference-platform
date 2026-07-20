# Layer 2 deployment issues & fixes

A running log of every non-trivial issue hit while building the Layer 2 EKS
platform, with root cause and fix. The point: a forker (or future me) shouldn't
have to rediscover any of these. See also
[ADR-0007](adr/0007-eks-cluster-foundation.md) and the plan workflow
[.github/workflows/terraform-plan.yml](../.github/workflows/terraform-plan.yml).

---

## 1. plan CI: mgmt account ID leaked into the public run log (fixed)

- **Where:** `.github/workflows/terraform-plan.yml`, `plan` job.
- **Symptom:** the `Configure AWS credentials` step printed
  `role-to-assume: arn:aws:iam::<MGMT_ACCOUNT_ID>:role/refplatform-github-actions`
  in clear text on a world-readable log.
- **Root cause:** `AWS_ROLE_ARN` was a repo **variable**. GitHub echoes an
  action's `with:` inputs in the log, and variables (unlike secrets) are not
  masked, so the ARN (which embeds the account ID) printed verbatim.
- **Fix:** moved the value to a repo **secret** `AWS_ROLE_ARN` (masked as `***`
  in the input echo), deleted the variable, and deleted the leaked run. Same
  treatment as `TF_STATE_BUCKET`.
- **Prevention:** any value embedding an account ID that is passed to an action
  input must be a secret, not a variable.

## 2. plan CI: OIDC assume-role "Not authorized" (fixed)

- **Where:** `plan` job, `Configure AWS credentials (OIDC)` step.
- **Symptom:** `Could not assume role with OIDC: Not authorized to perform
  sts:AssumeRoleWithWebIdentity`. `discover` and `validate` pass; only the cloud
  `plan` fails. This was the first time the plan workflow actually attempted the
  cross-account assume (the prior workflow was stale and never ran green).
- **Root cause:** this account emits **immutable-ID OIDC subjects**. A debug step
  printing the token claims showed the real `sub` was
  `repo:SamuelTillman@141371265/aws-eks-reference-platform@1302268994:pull_request`,
  with numeric owner/repo IDs appended. The trust policy matched the plain
  `repo:OWNER/REPO:*`, which the `@<id>` form never matches, so STS rejected it.
- **False lead:** switching the condition to the (always-plain) `repository`
  claim was rejected by AWS: `MalformedPolicyDocument ... must evaluate ...
  token.actions.githubusercontent.com:sub or ...:job_workflow_ref`. AWS *requires*
  the GitHub-OIDC trust to condition on `sub` (or `job_workflow_ref`).
- **Fix:** match `sub` against the immutable form, built from two new bootstrap
  variables `github_owner_id`/`github_repo_id` (public numeric IDs, not account
  IDs); empty falls back to the plain `repo:OWNER/REPO:*`. Get the IDs with
  `gh api repos/OWNER/REPO --jq '{owner: .owner.id, repo: .id}'`.
- **Prevention:** forkers whose accounts emit immutable subjects set those two
  vars; the plain form remains the default.
- **Status:** fixed (bootstrap re-applied; trust now matches the immutable sub).

## 3. plan CI: bootstrap stack fails on missing required variable (fixed)

- **Where:** `plan` job, `bootstrap` stack (surfaced when the OIDC fix touched
  `terraform/bootstrap`, so `discover` added it to the matrix).
- **Symptom:** `Error: No value for required variable` for `github_org`.
- **Root cause:** `terraform.tfvars` is gitignored, so CI has no value for
  bootstrap's required `github_org` (and the immutable-ID vars).
- **Fix:** the `plan` job exports the GitHub identity from the Actions context
  as `TF_VAR_github_org` / `github_repo` / `github_owner_id` / `github_repo_id`
  (`github.repository_owner`, `github.event.repository.name`,
  `github.repository_owner_id`, `github.repository_id`). Forkable and always
  matches the running repo; undeclared `TF_VAR_*` are ignored by other stacks.
- **Status:** fixed.

## 4. kubectl access: the --role-arn kubeconfig exec hangs

- **Where:** connecting to the `refplatform-dev` cluster from a workstation.
- **Symptom:** `aws eks update-kubeconfig --role-arn <OrganizationAccountAccessRole>`
  writes a working kubeconfig, but every `kubectl` call then hangs (the per-call
  `aws eks get-token --role-arn ...` exec did not return). The cluster itself was
  healthy: its endpoint resolved to public IPs and `/livez` returned 200 in
  &lt;0.5s, and the admin IP was on the endpoint allowlist.
- **Fix that works:** assume the account role once, export the temporary
  credentials, and run `update-kubeconfig` WITHOUT `--role-arn` so the exec uses
  the ambient creds:
  ```sh
  creds=$(aws sts assume-role --role-arn arn:aws:iam::<workloads-dev>:role/OrganizationAccountAccessRole \
            --role-session-name kubectl --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
  export AWS_ACCESS_KEY_ID=$(echo "$creds"|cut -f1) AWS_SECRET_ACCESS_KEY=$(echo "$creds"|cut -f2) AWS_SESSION_TOKEN=$(echo "$creds"|cut -f3)
  aws eks update-kubeconfig --name refplatform-dev --region us-east-1
  kubectl get nodes
  ```
- **Note:** the cluster creator (the assumed OrganizationAccountAccessRole) is the
  bootstrap cluster-admin; the SSO Administrator role is also a cluster-admin
  access entry. An expired SSO token presents the same hang, so check
  `aws sts get-caller-identity` first.

## 5. ArgoCD port-forward: reach it over HTTP, not HTTPS

- **Where:** reaching the ArgoCD UI via `kubectl -n argocd port-forward
  svc/argocd-server 8080:443`.
- **Symptom:** the port-forward listens and `kubectl get`/`logs` work, but every
  browser/curl request to `https://localhost:8080` returns nothing (curl "HTTP
  000"), and the port-forward logs `an error occurred forwarding 8080 -> 8080:
  ... read: connection reset by peer`. The `argocd-server` pod is `1/1` Ready with
  0 restarts and healthy logs, so it looks like the tunnel is broken when it is
  not.
- **Root cause:** the argo-cd Helm install runs the server in **insecure mode**
  (`server.insecure: "true"` in `argocd-cmd-params-cm`), i.e. it serves **plain
  HTTP** on container port 8080 (TLS is meant to be terminated by an ingress, a
  later increment, ADR-0010 §4). Hitting it with `https://` sends a TLS
  ClientHello to a plaintext listener, which reads the handshake bytes as a bad
  request and **resets the connection**, so the TLS handshake never completes and
  the client sees nothing. Isolation proof: port-forwarding the *same pod's*
  metrics port 8083 (plain HTTP) returned 200, only the 8080 request over TLS
  reset.
- **Fix:** use **`http://localhost:8080`** (not https).
- **Note (ADR-0015):** the local `admin` account no longer exists, so there is no
  password and the in-cluster UI has no login path. Use the kubeconfig-backed
  local dashboard instead: `argocd admin dashboard -n argocd` (or
  `argocd app list --core`), authenticated as your Identity Center identity.
- **Prevention:** until an ingress terminates TLS, ArgoCD is HTTP-only over the
  port-forward. A "connection reset by peer" on a healthy pod after an HTTPS
  request is the tell that the listener is plaintext, retry with `http://` before
  suspecting the tunnel, creds, or the endpoint allowlist.

## 7. kube-prometheus-stack / Kyverno show OutOfSync-but-Healthy in ArgoCD

- **Where:** the `kube-prometheus-stack` and `kyverno` ArgoCD Applications
  ([ADR-0013](adr/0013-observability.md), [ADR-0014](adr/0014-policy-kyverno.md)).
- **Symptom:** both settle at **Health = Healthy** (all pods Running, functional,
  Kyverno enforcement verified working) but **Sync = OutOfSync**, and with
  `selfHeal: true` ArgoCD keeps re-applying them.
- **Root cause:** cosmetic, not a real failure. These charts trip the well-known
  ArgoCD server-side-apply drift: admission/conversion webhooks and the operators
  mutate objects after apply (CRD `caBundle` injection, defaulted fields,
  `managedFields` ownership), so ArgoCD's live-vs-desired diff never reaches
  clean. `ServerSideApply=true` (already set) reduces but does not eliminate it.
- **Fix (optional, cosmetic):** add `spec.ignoreDifferences` to each Application
  for the noisy fields (webhook `caBundle`, conversion strategy, the
  operator-managed fields), or accept OutOfSync-but-Healthy as normal for these
  charts. Left as OutOfSync here since it is harmless and the components work.
- **Prevention:** judge these Applications by **Health**, not Sync. OutOfSync +
  Healthy on a webhook-heavy Helm chart is expected; only OutOfSync + Degraded/
  Missing is a real problem.

## 6. Karpenter controller: iam:ListInstanceProfiles AccessDenied (fixed)

- **Where:** `terraform/eks/karpenter.tf`, the Karpenter controller IAM policy
  ([ADR-0011](adr/0011-karpenter-autoscaling.md)).
- **Symptom:** the controller ran and provisioned nodes fine, but its log looped
  `AccessDenied ... iam:ListInstanceProfiles` every few seconds from the
  `instanceprofile.garbagecollection` reconciler.
- **Root cause:** the design pre-creates the node instance profile and pins it on
  the EC2NodeClass (`spec.instanceProfile`) to keep instance-profile *management*
  out of the controller policy. That removed Create/Delete/Add/Remove/Tag, but
  Karpenter v1.14 still runs an instance-profile **garbage collector** that calls
  `iam:ListInstanceProfiles` (by path prefix) regardless of whether the profile is
  static. The policy granted `GetInstanceProfile` but not `ListInstanceProfiles`,
  so the GC loop 403'd. Non-fatal (the launch path uses the static profile +
  `GetInstanceProfile`), but a broken controller spamming AccessDenied is not
  acceptable for an audit-reference platform.
- **Fix:** add `iam:ListInstanceProfiles` (Resource `*`, an account-level read
  that does not take a resource ARN). Errors cleared within ~30s of apply.
- **Prevention:** even with a static `spec.instanceProfile`, Karpenter v1 needs
  `iam:ListInstanceProfiles` for its GC controller. When translating the upstream
  controller policy, keep the read/list actions (`GetInstanceProfile`,
  `ListInstanceProfiles`) even if you drop the management ones. Verify by tailing
  the controller log for `AccessDenied` after the first apply, not just by
  checking that a node launches.

## 7. ArgoCD shows Helm apps `OutOfSync` (and briefly `Degraded`) while Healthy

- **Where:** the `kube-prometheus-stack` and `kyverno` Applications after a
  rebuild.
- **Symptom:** apps sit at `OutOfSync` indefinitely while reporting `Healthy`, and
  during the first minute or two of a rebuild they can flash `Degraded` or
  `Missing`. The `root` app also flips between `Synced` and `OutOfSync`. Nothing is
  actually broken: pods run, Grafana serves, Kyverno admits and blocks.
- **Root cause:** two separate, benign effects.
  1. **Startup ordering.** `Degraded`/`Missing` in the first minutes is just the
     chart still installing (CRDs, webhooks, pods not yet ready). It clears on its
     own; do not chase it.
  2. **Server-side-apply field drift.** Both charts are synced with
     `ServerSideApply=true` (needed, their CRDs exceed the client-side
     last-applied-annotation limit). Their own operators and webhooks then mutate
     fields on the objects they own (webhook `caBundle`, defaulted fields), so
     ArgoCD's desired-vs-live diff never reaches zero. With `selfHeal` on, ArgoCD
     harmlessly re-applies; it does not fight the operator.
- **Fix:** none required. It is cosmetic. If the noise matters, add
  `ignoreDifferences` entries to the Application for the specific
  operator-managed fields (e.g. webhook `caBundle`) rather than turning off
  ServerSideApply, which would break the CRD apply.
- **Prevention:** judge these components by **Health** and real behavior, not by
  `Sync` status. Wait ~2 minutes after a rebuild before reading any of it; the
  first status you see is almost always mid-install.
