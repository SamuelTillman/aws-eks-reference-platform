# Manual Bootstrap

Infrastructure as code has a chicken and egg problem: something must exist before Terraform can run. This document is the complete, honest list of manual (ClickOps) steps. Everything after step 6 is code.

## 1. Create the management account

- Sign up at aws.amazon.com with a dedicated alias, e.g. `you+aws-mgmt@yourdomain.com`
- Use a business payment method if the platform belongs to an entity
- This account will run **nothing** except AWS Organizations, IAM Identity Center, and billing

## 2. Lock down root

- Enable MFA on the root user immediately (a hardware key is preferred)
- Don't create IAM users. Don't create access keys. Root isn't used again except for [tasks that require root](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-tasks.html)

## 3. Enable AWS Organizations

- Console → AWS Organizations → Create organization (all features enabled)

## 4. Enable IAM Identity Center

- Console → IAM Identity Center → Enable (in your home region)
- Create your admin user and assign it the `AdministratorAccess` permission set for the management account
- From here on, all human access is SSO. Configure locally:

```bash
aws configure sso
```

## 5. Verify email aliasing

Each AWS account needs a unique email. Plus addressing gives you one inbox with many addresses:

```
you+aws-mgmt@yourdomain.com
you+aws-security@yourdomain.com
you+aws-shared@yourdomain.com
you+aws-dev@yourdomain.com
you+aws-prod@yourdomain.com
```

Send yourself a test email to confirm your mail host supports it.

## 6. First Terraform run (local, SSO credentials)

The state backend can't store its own state remotely on the first run. Bootstrap locally:

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # then edit values
terraform init
terraform apply          # creates state bucket plus GitHub OIDC provider and role

# The bucket name embeds your account ID, so it's supplied out-of-band (never
# committed). Copy the example, fill in the bucket from `terraform output`:
cp backend.hcl.example backend.hcl             # set bucket = <state bucket>
terraform init -backend-config=backend.hcl -migrate-state
```

> **Why `-backend-config`?** The state bucket name contains your management
> account ID, and this is a public repo. `versions.tf` keeps only non-sensitive
> backend settings; the `bucket` lives in a gitignored `backend.hcl`. See
> ADR-0003. Every `terraform init` in either stack needs the
> `-backend-config=backend.hcl` flag.

## 7. Everything else is code

- `terraform/org/` holds OUs, member accounts, and SCPs (run locally with SSO first; CI takes over via OIDC)
- All later layers deploy through GitHub Actions using the OIDC role from step 6

## Root email hygiene for vended accounts

Accounts created by `terraform/org/` get root passwords that were never set. Leave them unset. If you ever need root on a member account, use the password reset flow against its alias, then set MFA and walk away.
