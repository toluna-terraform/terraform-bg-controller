Blue Green Controller [Terraform module](https://registry.terraform.io/modules/toluna-terraform/controller/bg/latest)

### Description
This module implements the ability to create blue-green deployment of infrastructure


The following resources will be created:
- codebuild

## Requirements
The module requires some pre conditions

## Usage
```hcl
module "source_blue_green" {
  for_each = local.bg_envs
  source = "toluna-terraform/controller/bg"
  env_name = "${each.key}"
  app_name = local.app_name
  env_type = local.env_vars.env_type
  domain = "${local.env_vars.domain}."
  trigger_branch = "${each.value.trigger_branch}"
  pipeline_type = "${each.value.pipeline_type}"
  source_repository = "${repo_name}"
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.59 |


## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.59 |
| <a name="provider_null"></a> [null](#provider\_null) | >= 3.1.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="blue_green_controller"></a> [blue_green_controller](#module\blue_green_controller) | ../../ |  |

## Resources

| Name | Type |
|------|------|
resource |
| [aws_codebuild_webhook](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/aws_codebuild_webhook) | resource |
| [aws_codebuild_project](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/aws_codebuild_project) | resource |
| [aws_iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/aws_iam_role) | resource |
| [aws_iam_role_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/aws_iam_role_policy_attachment) | resource |
| [aws_s3_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/aws_s3_bucket) | resource |
| [aws_s3_bucket_object](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/aws_s3_bucket_object) | resource |

## Inputs
| Name | Description |
|------|------|
|env_name|Environment name|
|app_name|Application name|
|env_type|Environmanet type (I.E. prod or non-prod)|
|domain|domain for route53 weight shift|
|trigger_branch|the branch which PR on it will trigger the codebuild|
|pipeline_type|ci or cd|
|source_repository|the repository to listen for triggers|

## Outputs
No outputs.

