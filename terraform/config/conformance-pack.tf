# -----------------------------------------------------------------------------
# Org-wide baseline conformance pack (ADR-0009), deployed from the security
# account (the Config delegated admin, same path as the aggregator). It rolls a
# curated set of managed Config rules out to every member account so the
# platform's own hardening is continuously attested, not just set at deploy time.
#
# Behind an enable flag (cost discipline): a conformance pack bills per rule
# evaluation, so it can be stood down to zero like the other paid detectors.
# Org conformance packs cover member accounts only; the management account is not
# included (an AWS limitation) and would need a standalone pack.
# -----------------------------------------------------------------------------

# The org conformance pack targets the MEMBER accounts (see excluded_accounts
# below). The config-conforms SLR is created in the management account anyway:
# it is the documented prerequisite for ANY conformance-pack activity there (a
# delegated admin cannot create it), so keeping it means a standalone management
# conformance pack can be added later without re-hitting the SLR gap. See
# layer1-issues #10.
resource "aws_iam_service_linked_role" "config_conforms" {
  count            = var.enable_conformance_pack ? 1 : 0
  aws_service_name = "config-conforms.amazonaws.com"
}

resource "aws_config_organization_conformance_pack" "baseline" {
  count    = var.enable_conformance_pack ? 1 : 0
  provider = aws.security

  name          = "${var.name_prefix}-baseline"
  template_body = file("${path.module}/conformance-pack.yaml")

  # Exclude the management account. Org conformance packs do not converge in the
  # management account (the deployment hangs in CREATE_IN_PROGRESS with no backing
  # stack, even with the SLR present); member accounts are the supported targets,
  # and mgmt holds no workloads to attest. layer1-issues #10.
  excluded_accounts = [local.mgmt_account_id]

  # Org conformance packs roll out to every member account sequentially and
  # routinely exceed the provider's default 10m create wait (layer1-issues).
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [
    aws_iam_service_linked_role.config_conforms,
    aws_config_configuration_aggregator.org,
    module.config_management,
    module.config_security,
    module.config_shared_services,
    module.config_workloads_dev,
    module.config_workloads_prod,
  ]
}
