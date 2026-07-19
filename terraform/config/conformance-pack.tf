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

resource "aws_config_organization_conformance_pack" "baseline" {
  count    = var.enable_conformance_pack ? 1 : 0
  provider = aws.security

  name          = "${var.name_prefix}-baseline"
  template_body = file("${path.module}/conformance-pack.yaml")

  # Org conformance packs roll out to every member account sequentially and
  # routinely exceed the provider's default 10m create wait (layer1-issues).
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [
    aws_config_configuration_aggregator.org,
    module.config_management,
    module.config_security,
    module.config_shared_services,
    module.config_workloads_dev,
    module.config_workloads_prod,
  ]
}
