data "aws_iam_policy_document" "codebuild_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
        }
    }
}

data "aws_route53_zone" "public" {
  name         = var.domain
  private_zone = false
}

data "aws_caller_identity" "current" {}
