# prepare lambda zip file
data "archive_file" "merge_waiter_zip" {
    type        = "zip"
    source_file  = "${path.module}/lambda/merge_waiter.js"
    output_path = "${path.module}/lambda/lambda.zip"
}

resource "aws_lambda_function" "merge_waiter" {
  filename      				 = "${path.module}/lambda/lambda.zip"
  function_name 				 = "${var.app_name}-${var.env_type}-merge-waiter"
  role          				 = aws_iam_role.merge_waiter.arn
  handler       				 = "merge_waiter.handler"
  runtime       				 = "nodejs14.x"
  timeout       				 = 180
  reserved_concurrent_executions = 100
  source_code_hash = filebase64sha256("${path.module}/lambda/lambda.zip")
  kms_key_arn 	   = "ckv_km"
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      APP_NAME = var.app_name
      ENV_TYPE = var.env_type
    }
  }
}

# IAM
resource "aws_iam_role" "merge_waiter" {
  name = "lambda-role-${var.app_name}_${var.env_type}-merge-waiter"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
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
    role       = "${aws_iam_role.merge_waiter.name}"
    policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_dynamodb_table" "merge_waiter" {
  name     = "MergeWaiter-${var.app_name}-${var.env_type}"
  hash_key         = "APPLICATION"
  billing_mode = "PAY_PER_REQUEST"
  attribute {
    name = "APPLICATION"
    type = "S"
  }
}

