# prepare lambda zip file
data "archive_file" "notifier_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/notifier.js"
  output_path = "${path.module}/lambda/lambda.zip"
}


resource "aws_lambda_layer_version" "aws_sdk" {
  filename   = "${path.module}/layer/layer.zip"
  layer_name = "${var.app_name}-${var.env_type}-aws_sdk"

  compatible_runtimes = ["nodejs20.x"]
}

resource "aws_lambda_function" "notifier" {
  filename         = "${path.module}/lambda/lambda.zip"
  function_name    = "${var.app_name}-${var.env_type}-notifier"
  role             = aws_iam_role.notifier.arn
  handler          = "notifier.handler"
  runtime          = "nodejs20.x"
  layers           = [aws_lambda_layer_version.aws_sdk.arn]
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


resource "aws_sns_topic" "builds" {
  name = "${var.app_name}-${var.env_type}-notifier-sns"
}

resource "aws_sns_topic_subscription" "sns-topic" {
  topic_arn = aws_sns_topic.builds.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notifier.arn
}

resource "aws_lambda_permission" "sns_permission_to_invoke_lambda" {
  statement_id_prefix  = "AllowExecutionFromSNS_${var.app_name}_${var.env_type}_notifier"
  action        = "lambda:InvokeFunction"
  function_name = "${var.app_name}-${var.env_type}-notifier"
  principal     = "sns.amazonaws.com"
  source_arn = "arn:aws:sns:us-east-1:${data.aws_caller_identity.aws_profile.account_id}:${var.app_name}-${var.env_type}-notifier-sns"
}

data "aws_iam_policy_document" "builds" {
  statement {
    sid       = "TrustCloudWatchEvents"
    effect    = "Allow"
    resources = [aws_sns_topic.builds.arn]
    actions   = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "builds_events" {
  arn    = aws_sns_topic.builds.arn
  policy = data.aws_iam_policy_document.builds.json
}

resource "aws_cloudwatch_event_rule" "builds" {
  name          = "codebuild-source-merge-${var.app_name}-${var.env_type}"
  event_pattern = <<PATTERN
{
    "source": ["aws.codebuild"],
    "detail-type": ["CodeBuild Build State Change"],
    "detail": {
        "build-status": [
            "SUCCEEDED", 
            "FAILED",
            "STOPPED"
        ],
        "project-name": ${jsonencode(var.project_names)}
    }
}
PATTERN

}

resource "aws_cloudwatch_event_target" "builds" {
  target_id = "codebuild-source-merge-${var.app_name}-${var.env_type}"
  rule      = aws_cloudwatch_event_rule.builds.name
  arn       = aws_sns_topic.builds.arn
  input_transformer {
    input_paths = {
      project_name = "$.detail.project-name",
      status       = "$.detail.build-status",
    }
    input_template = <<EOF
{
  "project_name": "<project_name>",
  "build_status": "<status>"
}
EOF
  }
}