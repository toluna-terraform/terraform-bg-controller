# ---- iam role for Lambdas
resource "aws_iam_role" "lambda-role" {
  name = "lambda-role-${local.app_name}-${local.env_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Attach inline policy to access CloudWatch, etc
resource "aws_iam_role_policy" "InlinePolicyForLambda" {
  name = "inline-policy-cloud-watch-${local.app_name}-${local.env_name}"
  role = aws_iam_role.lambda-role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:*:${local.aws_account_id}:function:*"
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogStream",
                "logs:CreateLogGroup"
            ],
            "Resource": "*"
        }
    ]
})
}

# Attach SF access
resource "aws_iam_policy_attachment" "attach-sf-access" {
  name       = "attach-sf-access-${local.app_name}-${local.env_name}"
  roles      = [ aws_iam_role.lambda-role.name ]
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
}

