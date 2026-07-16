# -----------------------------------------------------------------------------
# VPC Flow Logs -> central archive (ADR-0006 §Observability).
#
# The flow log is created in THIS VPC's account (the module's provider) and
# delivers to the cross-account bucket owned by the security account. Enabled
# per-VPC by passing flow_log_destination_arn; the destination bucket policy +
# KMS grants for delivery live in the root stack (flowlogs.tf).
# -----------------------------------------------------------------------------

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = var.flow_log_destination_arn
  max_aggregation_interval = 600

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}
