# prepare lambda zip file
data "archive_file" "notifier_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/notifier.js"
  output_path = "${path.module}/lambda/lambda.zip"
}

resource "aws_lambda_function" "notifier" {
  filename         = "${path.module}/lambda/lambda.zip"
  function_name    = "${var.app_name}-${var.env_type}-notifier"
  role             = aws_iam_role.notifier.arn
  handler          = "notifier.handler"
  runtime          = "nodejs16.x"
  timeout          = 180
  source_code_hash = filebase64sha256("${path.module}/lambda/lambda.zip")
  environment {
    variables = {
      APP_NAME          = var.app_name
      SOURCE_REPOSITORY = var.source_repository
    }
  }
}

# IAM
resource "aws_iam_role" "notifier" {
  name = "lambda-role-${var.app_name}_${var.env_type}-notifier"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "codebuild.amazonaws.com",
          "codedeploy.amazonaws.com",
          "codepipeline.amazonaws.com",
          "lambda.amazonaws.com",
          "ssm.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "role-pipeline-execution" {
  role       = aws_iam_role.notifier.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
