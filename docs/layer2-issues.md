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

## 7. Kyverno app sits `OutOfSync` while `Healthy` (unresolved, cosmetic)

- **Where:** the `kyverno` Application after a rebuild. (Earlier drafts of this
  entry also blamed `kube-prometheus-stack` and `external-secrets`; that was
  wrong, see "corrections" below.)
- **Symptom:** `kyverno` reports `OutOfSync` indefinitely while `Healthy`. Eleven
  `CustomResourceDefinition` resources are listed as the OutOfSync members. The
  engine works: pods run, policies are Ready, and admission enforcement provably
  blocks a `:latest` pod.
- **What was actually measured** (rather than assumed):
  - The live CRD has `spec.conversion: {strategy: None}`; the chart ships the CRD
    with **no `spec.conversion` field at all**. The API server defaults it.
  - A full structural comparison of chart-rendered CRD vs live CRD found
    `/spec/conversion` to be the **only** difference.
  - The CRDs use `conversion strategy: None`, so webhook `caBundle` injection is
    **not** involved (an earlier draft of this entry claimed it was).
- **Fixes attempted and REVERTED, both failed:**
  1. `ignoreDifferences` on `/spec/conversion` for `CustomResourceDefinition`.
     Confirmed the rule landed on the in-cluster Application; status unchanged
     through a hard refresh.
  2. Additionally `RespectIgnoreDifferences=true` in `syncOptions` (the documented
     way to make `ignoreDifferences` count toward sync status rather than just the
     diff view). Confirmed the option landed; status still unchanged.
- **Status: unresolved and deliberately left alone.** It is cosmetic: the
  component is Healthy and functionally verified. Something beyond the one
  structural field is driving ArgoCD's diff for these large CRDs, and it was not
  worth more cluster time to chase. The reverted attempts are recorded here so the
  next person does not repeat them.
- **Prevention / guidance:** judge these components by **Health and real
  behavior, not Sync status**, and wait ~2 minutes after a rebuild before reading
  any status at all; the first thing you see is almost always mid-install.
- **Corrections to earlier versions of this entry** (kept visible on purpose):
  - `kube-prometheus-stack` and `external-secrets` were described as persistently
    OutOfSync/Degraded. They are **not**. Both settle to `Synced`/`Healthy`; what
    was observed was transient install state (CRDs, webhook certs, pods starting).
  - The cause was described as ServerSideApply/webhook-`caBundle` drift. That was
    a guess and it was wrong.

## 8. External Secrets v2 serves `external-secrets.io/v1`, not `v1beta1`

- **Where:** `gitops/external-secrets/` ([ADR-0016](adr/0016-platform-secrets-external-secrets.md)).
- **Risk (caught before applying, never hit):** almost every ESO tutorial, blog
  post and older doc writes `ClusterSecretStore` / `ExternalSecret` as
  `apiVersion: external-secrets.io/v1beta1`. Against the chart used here
  (`external-secrets` 2.8.0, app **v1.18.2**) that API is **not served**, so
  copied manifests fail to apply and the secret never materializes, which then
  presents as an unrelated Grafana crash-loop waiting for a Secret that will never
  arrive.
- **Root cause:** ESO v2 graduated the CRDs to `v1` and dropped `v1beta1` from
  `servedVersions`.
- **Fix:** use `external-secrets.io/v1`. Determined by rendering the chart and
  reading the CRDs directly rather than trusting documentation:
  ```bash
  helm template eso external-secrets/external-secrets --version 2.8.0 --include-crds \
    | yq '. | select(.kind=="CustomResourceDefinition") | .spec.versions[].name'
  ```
- **Prevention:** for any operator chart, confirm the **served** CRD apiVersion
  from the chart itself before writing custom resources against it. Pinned chart
  versions and copied manifests drift apart silently.

## 9. Secrets Manager soft-delete blocks the next rebuild

- **Where:** `terraform/eks/external-secrets.tf` ([ADR-0016](adr/0016-platform-secrets-external-secrets.md)).
- **Symptom (anticipated and designed out):** destroying a stack that owns an
  `aws_secretsmanager_secret`, then rebuilding it, fails with the name
  *already scheduled for deletion*. The platform is built to be torn down and
  rebuilt on demand ([ADR-0008](adr/0008-cicd-lifecycle-teardown-rebuild.md)), so
  this would have broken the rebuild button for 7 to 30 days.
- **Root cause:** Secrets Manager does not hard-delete. It schedules deletion with
  a recovery window (default 30 days, minimum 7), and the **secret name stays
  reserved** for that entire window.
- **Fix:** `recovery_window_in_days = 0` on secrets owned by a teardown-target
  stack, which frees the name immediately.
- **Trade-off:** zero means no accidental-deletion recovery. Correct for a
  generated, per-rebuild credential; **wrong** for a secret holding something
  irreplaceable, which belongs in an always-on stack with a normal window instead.
- **Prevention:** decide per secret whether it is cluster-scoped (rotate freely,
  window 0) or must outlive a teardown (always-on stack, keep the window).

