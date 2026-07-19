# -----------------------------------------------------------------------------
# Seed the platform permission boundary in the SECURITY account (ADR-0012).
#
# The boundary policy is created per-account by whichever stack owns that account:
# bootstrap seeds management, cicd seeds shared-services/dev/prod. This seeds the
# security account, the last one without it, so the human SSO Administrator
# boundary (identity stack) can resolve the customer-managed boundary in every
# account its permission sets are assigned to.
# -----------------------------------------------------------------------------

module "boundary_security" {
  source    = "../modules/permission-boundary"
  providers = { aws = aws.security }
  name      = "${var.name_prefix}-permission-boundary"
}
