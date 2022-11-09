# prepare lambda zip file
data "archive_file" "merge_waiter_zip" {
    type        = "zip"
    source_file  = "${path.module}/lambda/merge_waiter.js"
    output_path = "${path.module}/lambda/lambda.zip"
}

resource "aws_lambda_function" "merge_waiter" {
  filename      = "${path.module}/lambda/lambda.zip"
  function_name = "${var.app_name}-${var.env_type}-merge-waiter"
  role          = aws_iam_role.merge_waiter.arn
  handler       = "merge_waiter.handler"
  runtime       = "nodejs14.x"
  timeout       = 180
  source_code_hash = filebase64sha256("${path.module}/lambda/lambda.zip")
  environment {
    variables = {
      APP_NAME = var.app_name
    }
  }
}

# IAM
resource "aws_iam_role" "merge_waiter" {
  name = "lambda-role-${var.app_name}-${var.env_type}-merge-waiter"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "codedeploy.amazonaws.com",
          "lambda.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "inline_merge_status_update_policy" {
  name   = "inline-policy-${var.app_name}-${var.env_type}-merge-waiter"
  role   = aws_iam_role.merge_waiter.id
  policy = data.aws_iam_policy_document.inline_merge_status_update_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "role-lambda-execution" {
    role       = "${aws_iam_role.merge_waiter.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "role-lambda-ssm" {
    role       = "${aws_iam_role.merge_waiter.name}"
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_role_policy_attachment" "role-cloudwatch" {
    role       = "${aws_iam_role.merge_waiter.name}"
    policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "role-codedeploy" {
    role       = "${aws_iam_role.merge_waiter.name}"
    policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployFullAccess"
}

