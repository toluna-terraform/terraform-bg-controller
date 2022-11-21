variable "pipeline_type" {
  type = string
}

variable "trigger_branch" {
  type = string
}

variable "env_name" {
  type = string
}

variable "app_name" {
  type = string
}

variable "app_type" {
  default = "ecs"
  type = string
}

variable "domain" {
  type = string
}

variable "env_type" {
  type = string
}

variable "path_pattern" {
  type = string
}

variable "source_repository" {
    type = string
}

variable "is_managed_env" {
    type = string
}

variable "bucket_id" {
  type = string
}

variable "aws_profile" {
  type = string
}

variable "sq_version" {
  type = string
  default = "4.7.0.2747"
}

variable "sq_enabled" {
  type = bool
  default = false
}