data "aws_iam_policy_document" "inline_merge_status_update_policy_doc" {
  statement {
    actions = [
      "ssm:*"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "states:*"
    ]
    resources = ["*"]
  }
}