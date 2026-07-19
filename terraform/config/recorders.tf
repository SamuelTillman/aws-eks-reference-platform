# -----------------------------------------------------------------------------
# A Config recorder in every account, each delivering to the central bucket.
# One module instance per account, wired to that account's provider alias.
# All depend on the bucket policy so delivery is authorized before recording.
# -----------------------------------------------------------------------------

module "config_management" {
  source                   = "./modules/account-config"
  name_prefix              = var.name_prefix
  bucket_name              = aws_s3_bucket.config.id
  permission_boundary_name = "${var.name_prefix}-permission-boundary"

  providers  = { aws = aws }
  depends_on = [aws_s3_bucket_policy.config]
}

module "config_security" {
  source                   = "./modules/account-config"
  name_prefix              = var.name_prefix
  bucket_name              = aws_s3_bucket.config.id
  permission_boundary_name = "${var.name_prefix}-permission-boundary"

  providers  = { aws = aws.security }
  depends_on = [aws_s3_bucket_policy.config]
}

module "config_shared_services" {
  source                   = "./modules/account-config"
  name_prefix              = var.name_prefix
  bucket_name              = aws_s3_bucket.config.id
  permission_boundary_name = "${var.name_prefix}-permission-boundary"

  providers  = { aws = aws.shared_services }
  depends_on = [aws_s3_bucket_policy.config]
}

module "config_workloads_dev" {
  source                   = "./modules/account-config"
  name_prefix              = var.name_prefix
  bucket_name              = aws_s3_bucket.config.id
  permission_boundary_name = "${var.name_prefix}-permission-boundary"

  providers  = { aws = aws.workloads_dev }
  depends_on = [aws_s3_bucket_policy.config]
}

module "config_workloads_prod" {
  source                   = "./modules/account-config"
  name_prefix              = var.name_prefix
  bucket_name              = aws_s3_bucket.config.id
  permission_boundary_name = "${var.name_prefix}-permission-boundary"

  providers  = { aws = aws.workloads_prod }
  depends_on = [aws_s3_bucket_policy.config]
}
