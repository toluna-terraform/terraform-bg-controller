resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "s3-codepipeline-${var.app_name}-${var.env_type}"
  force_destroy = true
  tags = tomap({
    UseWithCodeDeploy = true
    created_by        = "terraform"
  })
}
resource "aws_s3_bucket_versioning" "codepipeline_bucket" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
  depends_on = [
    aws_s3_bucket.codepipeline_bucket
  ]
}

resource "aws_s3_bucket_public_access_block" "codepipeline_bucket" {
  bucket                  = aws_s3_bucket.codepipeline_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on = [
    aws_s3_bucket.codepipeline_bucket, aws_s3_bucket_versioning.codepipeline_bucket
  ]
}

data "aws_caller_identity" "current" {

}

provider "aws" {
  alias   = "prod"
  profile = "${var.app_name}-prod"
}

data "aws_caller_identity" "prod" {
  provider = aws.prod
}

resource "aws_s3_bucket_policy" "codepipeline_bucket" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
          "AWS": [
            "arn:aws:iam::${data.aws_caller_identity.prod.account_id}:root",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          ],
          "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:*",
      "Resource":[ 
        "arn:aws:s3:::${aws_s3_bucket.codepipeline_bucket.id}/*",
        "arn:aws:s3:::${aws_s3_bucket.codepipeline_bucket.id}"
      ]
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_ownership_controls" "source_codebuild_bucket" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "source_codebuild_bucket" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  acl    = "private"
  depends_on = [
    aws_s3_bucket.codepipeline_bucket, aws_s3_bucket_versioning.codepipeline_bucket,aws_s3_bucket_ownership_controls.source_codebuild_bucket
  ]
}

module "source_blue_green" {
  for_each          = var.apps
  source            = "./modules/bg_controller"
  env_name          = each.key
  app_name          = var.app_name
  app_type          = var.app_type
  env_type          = each.value.env_type
  path_pattern      = var.path_pattern
  domain            = var.domain
  aws_profile       = var.aws_profile
  ttl               = var.ttl
  is_managed_env    = each.value.is_managed_env
  trigger_branch    = each.value.pipeline_branch
  pipeline_type     = each.value.pipeline_type
  source_repository = var.source_repository
  bucket_id         = aws_s3_bucket.codepipeline_bucket.id
  depends_on = [
    aws_s3_bucket.codepipeline_bucket
  ]
}

module "merge_waiter" {
  source   = "./modules/merge_waiter"
  app_name = var.app_name
  env_type = var.env_type
}

data "aws_iam_policy_document" "cloudtrail_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_role_policy" {
  statement {
    actions = [
      "logs:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "cloudtrail_role" {
  name               = "role-${var.app_name}-${var.env_type}-cloud-trail"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role_policy.json
}

resource "aws_iam_role_policy" "cloudtrai_policy" {
  name   = "policy-${var.app_name}-${var.env_type}-cloud-trail"
  role   = aws_iam_role.cloudtrail_role.id
  policy = data.aws_iam_policy_document.cloudtrail_role_policy.json
}

resource "aws_cloudwatch_log_group" "trigger_pipeline" {
  name = "${var.app_name}-${var.env_type}-cloud-trail"
  retention_in_days = 3
}

resource "aws_cloudtrail" "trigger_pipeline" {
  name = "${var.app_name}-${var.env_type}-cloud-trail"
  s3_bucket_name = aws_s3_bucket.codepipeline_bucket.bucket
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trigger_pipeline.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_role.arn
  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = false
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${aws_s3_bucket.codepipeline_bucket.bucket}/*/source_artifacts.zip"]
    }
  }
}