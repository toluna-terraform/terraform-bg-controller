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
  app_name = local.app_name
  apps = local.bg_envs
  domain = local.env_vars.domain
  env_type = local.env_vars.env_type
  path_pattern = "^terraform/app.*"
  source_repository = "my_repo/${local.app_name}"
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
|apps|The list of apps for the ci/cd trigger|
|app_name|Application name|
|env_type|Environmanet type (I.E. prod or non-prod)|
|path_pattern|A pattern for listening to code changes|
|domain|domain for route53 weight shift|
|source_repository|the repository to listen for triggers|

## Outputs
No outputs.
