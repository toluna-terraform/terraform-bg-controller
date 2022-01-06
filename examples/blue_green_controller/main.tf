module "source_blue_green" {
  source = "../../"
  app_name = local.app_name
  apps = local.bg_envs
  domain = local.env_vars.domain
  env_type = local.env_vars.env_type
  path_pattern = "^terraform/app.*"
  source_repository = "my_repo/${local.app_name}"
}