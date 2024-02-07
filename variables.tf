variable "controller_config" {
  #type = map(string)
}

variable "apps" {
  type = map(object({
    env_type        = string,
    pipeline_branch = string,
    pipeline_type   = string,
    is_managed_env  = bool,
    sq_enabled      = bool
  }))
  default  = null
}

variable "app_name" {
  type     = string
  default  = null
}

variable "path_pattern" {
  type     = string
  default  = null
}

variable "source_repository" {
  type     = string
  default  = null
}

variable "env_type" {
  type     = string
  default  = null
}

variable "domain" {
  type     = string
  default  = null
}

variable "app_type" {
  type     = string
  default  = null
}

variable "aws_profile" {
  type     = string
  default  = null
}

variable "ttl" {
  type     = number
  default  = null
}
