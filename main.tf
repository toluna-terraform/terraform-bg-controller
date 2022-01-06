resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "s3-codepipeline-${var.app_name}-${var.env_type}"
  acl           = "private"
  force_destroy = true
  tags = tomap({
    UseWithCodeDeploy = true
    created_by        = "terraform"
  })
}

module "source_blue_green" {
  for_each = var.apps
  source = "./modules/bg_controller"
  env_name = "${each.key}"
  app_name = "${var.app_name}"
  env_type = "${each.value.env_type}"
  path_pattern = "${var.path_pattern}"
  domain = "${var.domain}"
  is_managed_env = "${each.value.is_managed_env}"
  trigger_branch = "${each.value.pipeline_branch}"
  pipeline_type = "${each.value.pipeline_type}"
  source_repository = "${var.source_repository}"
}