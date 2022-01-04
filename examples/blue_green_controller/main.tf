module "source_blue_green" {
  for_each = local.bg_envs
  source = "../../"
  env_name = "${each.key}"
  app_name = "my_app"
  env_type = "non-prod"
  domain = "example.com."
  trigger_branch = "test_branch"
  pipeline_type = "cd"
  source_repository = "test_repo/my_app"
}