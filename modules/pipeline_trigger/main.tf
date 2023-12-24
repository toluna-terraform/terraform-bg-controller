resource "aws_lambda_function" "pipeline_trigger" {
  filename         = "${path.module}/lambda/lambda.zip"
  function_name    = "${var.app_name}-${var.env_type}-pipeline-trigger"
  role             = aws_iam_role.pipeline_trigger.arn
  handler          = "pipeline_trigger.handler"
  runtime          = "nodejs20.x"
  timeout          = 180
  source_code_hash = filebase64sha256("${path.module}/lambda/lambda.zip")
  environment {
    variables = {
      APP_NAME = var.app_name
      ENV_NAME = var.env_type
    }
  }
}

# IAM
resource "aws_iam_role" "pipeline_trigger" {
  name = "lambda-role-${var.app_name}_${var.env_type}-pipeline-trigger"

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
          "s3.amazonaws.com",
          "ssm.amazonaws.com",
          "cloudwatch.amazonaws.com"
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
  role       = "${aws_iam_role.pipeline_trigger.name}"
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pipeline_trigger.arn
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.codepipeline_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket   = data.aws_s3_bucket.codepipeline_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.pipeline_trigger.arn
    events              = ["s3:ObjectCreated:Put", "s3:ObjectCreated:CompleteMultipartUpload", "s3:ObjectCreated:Copy"]
    filter_suffix       = "source_artifacts.zip"
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}
