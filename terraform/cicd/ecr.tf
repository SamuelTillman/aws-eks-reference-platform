# -----------------------------------------------------------------------------
# Central ECR in shared-services (ADR-0005 §3): immutable tags, scan on push,
# cross-account pull for the workload accounts, lifecycle expiry for cost.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)
  provider = aws.shared_services

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Allow the workload accounts to pull images.
data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid    = "AllowWorkloadAccountsPull"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${local.account_ids["workloads_dev"]}:root",
        "arn:aws:iam::${local.account_ids["workloads_prod"]}:root",
      ]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each   = aws_ecr_repository.this
  provider   = aws.shared_services
  repository = each.value.name
  policy     = data.aws_iam_policy_document.ecr_pull.json
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  provider   = aws.shared_services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent 30 tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = { type = "expire" }
      },
    ]
  })
}
