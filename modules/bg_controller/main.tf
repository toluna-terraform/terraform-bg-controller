locals {
  prefix = "codebuild"
  codebuild_name = "source"
  suffix = "${var.app_name}-${var.env_name}"
  source_repository_url = "https://bitbucket.org/${var.source_repository}"
}

resource "aws_codebuild_webhook" "pr_flow_hook_webhook" {
  project_name = aws_codebuild_project.pr_codebuild.name
  build_type   = "BUILD"
  filter_group {
    filter {
      type    = "EVENT"
      pattern = var.pipeline_type == "dev" ? "PUSH":"PULL_REQUEST_CREATED,PULL_REQUEST_UPDATED"
    }

    filter {
      type    = var.pipeline_type == "dev" ? "HEAD_REF" : "BASE_REF"
      pattern = var.trigger_branch
    }

    filter {
      type    = "FILE_PATH"
      pattern = var.pipeline_type == "dev" ? ".*" : "${var.path_pattern}"
    }
  }
}

resource "aws_codebuild_webhook" "merge_flow_hook_webhook" {
  count = var.pipeline_type == "dev" ? 0 : 1
  project_name = aws_codebuild_project.merge_codebuild[count.index].name
  build_type   = "BUILD"
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_MERGED"
    }

    filter {
      type    = "BASE_REF"
      pattern = var.trigger_branch
    }

    filter {
      type    = "FILE_PATH"
      pattern = "${var.path_pattern}"
    }
  }
}

resource "aws_codebuild_project" "pr_codebuild" {
  name          = var.pipeline_type == "dev" ? "${local.prefix}-${local.codebuild_name}-push-${local.suffix}" : "${local.prefix}-${local.codebuild_name}-pr-${local.suffix}"
  description   = "Pull source files from Git repo"
  build_timeout = "120"
  service_role  = aws_iam_role.source_codebuild_iam_role.arn

  artifacts {
    packaging = "ZIP"
    type      = "S3"
    override_artifact_name = true
    location  = "s3-codepipeline-${var.app_name}-${var.env_type}"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/code_build/${local.codebuild_name}/log-group"
      stream_name = "/code_build/${local.codebuild_name}/stream"
    }
  }

  source {
    type     = "BITBUCKET"
    location = local.source_repository_url
    buildspec = templatefile("${path.module}/templates/pr-created-buildspec-source.yml.tpl", { env_name = var.env_name, env_type = var.env_type,app_name = var.app_name,domain = var.domain,hosted_zone_id = data.aws_route53_zone.public.zone_id,is_managed_env = var.is_managed_env,pipeline_type = var.pipeline_type })
  }
  tags = tomap({
    Name        = "${local.prefix}-${local.codebuild_name}",
    environment = "${var.env_name}",
    created_by  = "terraform"
  })
}

resource "aws_codebuild_project" "merge_codebuild" {
  count = var.pipeline_type == "dev" ? 0 : 1
  name          = "${local.prefix}-${local.codebuild_name}-merge-${local.suffix}"
  description   = "Pull source files from Git repo"
  build_timeout = "120"
  service_role  = aws_iam_role.source_codebuild_iam_role.arn

  artifacts {
    packaging = "ZIP"
    type      = "S3"
    override_artifact_name = true
    location  = "s3-codepipeline-${var.app_name}-${var.env_type}"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/code_build/${local.codebuild_name}/log-group"
      stream_name = "/code_build/${local.codebuild_name}/stream"
    }
  }

  source {
    type     = "BITBUCKET"
    location = local.source_repository_url
    buildspec = templatefile("${path.module}/templates/merge-buildspec-source.yml.tpl", { env_name = var.env_name, env_type = var.env_type,app_name = var.app_name,domain = var.domain,hosted_zone_id = data.aws_route53_zone.public.zone_id})
  }
  tags = tomap({
    Name        = "${local.prefix}-${local.codebuild_name}",
    environment = "${var.env_name}",
    created_by  = "terraform"
  })
}

resource "aws_iam_role" "source_codebuild_iam_role" {
  name               = "role-${local.codebuild_name}-bg-${var.env_name}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "source_codebuild_iam_policy" {
  role = aws_iam_role.source_codebuild_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" // this policy should be changed to a new policy.
}

resource "aws_s3_bucket" "source_codebuild_bucket" {
  bucket        = "s3-codepipeline-${var.app_name}-${var.env_type}"
  acl           = "private"
  force_destroy = true
  tags = tomap({
    UseWithCodeDeploy = true
    created_by        = "terraform"
  })
  versioning {
    enabled = true
  }
}


resource "aws_s3_bucket_object" "folder" {
    bucket = "s3-codepipeline-${var.app_name}-${var.env_type}"
    acl    = "private"
    key    = "${var.env_name}/${var.pipeline_type}"
}