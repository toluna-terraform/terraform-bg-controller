data "aws_route53_zone" "public" {
  name         = var.domain
  private_zone = false
}

data "aws_acm_certificate" "public" {
  domain = var.domain
  types  = ["AMAZON_ISSUED"]
}

data "aws_caller_identity" "bitbucket_listener" {}