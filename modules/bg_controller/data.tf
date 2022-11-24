data "aws_iam_policy_document" "codebuild_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "codepipeline.amazonaws.com",
        "codedeploy.amazonaws.com",
        "codebuild.amazonaws.com",
        "cloudformation.amazonaws.com",
        "iam.amazonaws.com",
        "ssm.amazonaws.com",
        "route53.amazonaws.com"
      ]
    }
  }
}

data "aws_route53_zone" "public" {
  name         = var.domain
  private_zone = false
}

data "aws_caller_identity" "current" {}
