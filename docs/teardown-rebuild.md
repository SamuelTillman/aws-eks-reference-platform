# Teardown and rebuild

How to stand the platform down to near-zero cost and bring it back, mostly from
the GitHub Actions button ([ADR-0008](adr/0008-cicd-lifecycle-teardown-rebuild.md)).

The button is the **Platform Lifecycle** workflow: repo -> Actions -> Platform
Lifecycle (apply / destroy) -> Run workflow, then pick `stack`, `action`, and
(for destroy) type the stack name into `confirm`.

## What the button can and cannot do

- **Can:** apply/destroy `networking` and `eks`, and stand down/restore
  `security`. These are pure AWS API calls through the OIDC role.
- **Cannot:** apply `argocd`. ArgoCD lives inside the cluster, whose API endpoint
  is private and IP-restricted, so a GitHub runner cannot reach it. ArgoCD is a
  local one-liner instead (below). On teardown it needs no cluster access.

A rebuild reproduces the optimized cluster (EKS 1.35, spot, single NAT, endpoint
restricted to your IP) because the Lifecycle workflow feeds this environment's
profile: non-sensitive settings are set in the workflow, and the sensitive ones
come from secrets `EKS_PUBLIC_ACCESS_CIDRS` and `EKS_ADMIN_PRINCIPAL_ARNS`.

> **If your egress IP changed**, update the `EKS_PUBLIC_ACCESS_CIDRS` secret
> (repo -> Settings -> Secrets) to `["<new-ip>/32"]` before the eks rebuild, or
> you will not be able to reach the API endpoint.

## Teardown (to near-zero)

1. **ArgoCD** (local; it cannot go through CI). With a fresh SSO token:
   ```sh
   aws sso login --profile refplatform-mgmt
   AWS_PROFILE=refplatform-mgmt terraform -chdir=terraform/argocd destroy -auto-approve
   ```
   If the cluster is already gone (so `destroy` cannot reach it), just forget the
   releases instead, no cluster access needed:
   ```sh
   terraform -chdir=terraform/argocd state rm helm_release.root_app helm_release.argocd
   ```
2. **Button:** `stack=eks`, `action=destroy`, `confirm=eks`. (~10 min; the cluster
   deletion also removes ArgoCD if it was still running.)
3. **Button:** `stack=networking`, `action=destroy`, `confirm=networking`. A guard
   refuses this until the cluster is gone, so run it after step 2. (~5 min)
4. **Optional, for true near-zero:** `stack=security`, `action=destroy`,
   `confirm=security` disables GuardDuty/Security Hub (trades away audit coverage
   while idle). AWS Config has no off switch; its idle cost is small.

After steps 1-3 the ~$245/mo of cluster + NAT + Transit Gateway is $0; only the
Layer 1 governance (Config, Security Hub unless stood down, CloudTrail, S3)
remains, roughly $15-40/mo.

## Rebuild

1. `aws sso login --profile refplatform-mgmt` (and update `EKS_PUBLIC_ACCESS_CIDRS`
   if your IP changed).
2. If you stood down security: **Button** `stack=security`, `action=apply`.
3. **Button:** `stack=networking`, `action=apply`. (~5 min; single NAT)
4. **Button:** `stack=eks`, `action=apply`. (~15 min; EKS 1.35, spot, endpoint
   restricted to your IP, your admin roles mapped)
5. **ArgoCD** (local one-liner; your IP is on the allowlist from step 4):
   ```sh
   AWS_PROFILE=refplatform-mgmt terraform -chdir=terraform/argocd \
     init -backend-config=backend.hcl && \
   AWS_PROFILE=refplatform-mgmt terraform -chdir=terraform/argocd apply -auto-approve
   ```
6. **kubectl** (see [layer2-issues.md](layer2-issues.md) #4 for the auth note):
   ```sh
   creds=$(aws --profile refplatform-mgmt sts assume-role \
     --role-arn arn:aws:iam::<workloads-dev>:role/OrganizationAccountAccessRole \
     --role-session-name kubectl --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
   export AWS_ACCESS_KEY_ID=$(echo "$creds"|cut -f1) AWS_SECRET_ACCESS_KEY=$(echo "$creds"|cut -f2) AWS_SESSION_TOKEN=$(echo "$creds"|cut -f3)
   aws eks update-kubeconfig --name refplatform-dev --region us-east-1
   kubectl get nodes
   ```

## Fully automating the ArgoCD rebuild (future)

To make step 5 a button too, the Lifecycle workflow would temporarily add the
runner's IP to the cluster's `publicAccessCidrs` (via
`aws eks update-cluster-config`), apply ArgoCD, then remove it, keeping the
endpoint private the rest of the time. Deferred; the local one-liner is fine for
now.
