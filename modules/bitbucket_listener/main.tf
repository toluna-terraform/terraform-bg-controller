resource "aws_api_gateway_rest_api" "bitbucket_listener" {
  name = "bitbucket_listener"
    endpoint_configuration {
    types = ["PRIVATE"]
  }
}

resource "aws_api_gateway_rest_api_policy" "bitbucket_listener" {
  rest_api_id = aws_api_gateway_rest_api.bitbucket_listener.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "execute-api:Invoke",
      "Resource": "${aws_api_gateway_rest_api.bitbucket_listener.execution_arn}"
    }
  ]
}
EOF
}

resource "aws_api_gateway_resource" "bitbucket_listener" {
  parent_id   = aws_api_gateway_rest_api.bitbucket_listener.root_resource_id
  path_part   = "v1"
  rest_api_id = aws_api_gateway_rest_api.bitbucket_listener.id
}

resource "aws_api_gateway_method" "bitbucket_listener" {
  authorization = "NONE"
  http_method   = "POST"
  resource_id   = aws_api_gateway_resource.bitbucket_listener.id
  rest_api_id   = aws_api_gateway_rest_api.bitbucket_listener.id
}

resource "aws_sqs_queue" "bitbucket_listener" {
  name                        = "bitbucket-listener.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

resource "aws_api_gateway_integration" "bitbucket_listener" {
  rest_api_id             = aws_api_gateway_rest_api.bitbucket_listener.id
  resource_id             = aws_api_gateway_resource.bitbucket_listener.id
  http_method             = aws_api_gateway_method.bitbucket_listener.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.bitbucket_listener.arn
  uri                     = "arn:aws:apigateway:us-east-1:sqs:path/${data.aws_caller_identity.bitbucket_listener.account_id}/${aws_sqs_queue.bitbucket_listener.name}"
  passthrough_behavior = "NEVER"
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body&MessageGroupId=${var.app_name}-${var.env_type}"
    }
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }
} 

resource "aws_api_gateway_stage" "bitbucket_listener" {
  deployment_id = aws_api_gateway_deployment.bitbucket_listener.id
  rest_api_id   = aws_api_gateway_rest_api.bitbucket_listener.id
  stage_name    = "bitbucket_listener"
  depends_on = [
    aws_api_gateway_rest_api_policy.bitbucket_listener,aws_api_gateway_stage.bitbucket_listener
  ]
}


resource "aws_api_gateway_deployment" "bitbucket_listener" {
  rest_api_id = aws_api_gateway_rest_api.bitbucket_listener.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.bitbucket_listener.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "bitbucket_listener" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bitbucket_listener.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "arn:aws:execute-api:us-east-1:047763475875:${aws_api_gateway_rest_api.bitbucket_listener.id}/*/${aws_api_gateway_method.bitbucket_listener.http_method}${aws_api_gateway_resource.bitbucket_listener.path}"
}

resource "aws_lambda_layer_version" "lambda_layer" {
  filename   = "${path.module}/layer/layer.zip"
  layer_name = "bitbucket_listener"

  compatible_runtimes = ["python3.8"]
}

data "archive_file" "lambda_zip" {
 type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "bitbucket_listener" {
  filename      = "${path.module}/lambda.zip"
  function_name = "bitbucket_listener"
  role          = aws_iam_role.bitbucket_listener.arn
  handler       = "bitbucket_listener.lambda_handler"
  runtime       = "python3.8"
  layers = [aws_lambda_layer_version.lambda_layer.arn]
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
}

resource "null_resource" "remove_zip" {
  provisioner "local-exec" {
    when = create
    command = "rm -f ${path.module}/lambda.zip"
  }
  depends_on = [aws_lambda_function.bitbucket_listener]
}

# IAM
resource "aws_iam_role" "bitbucket_listener" {
  name = "bitbucket_listener"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "sqs.amazonaws.com",
          "apigateway.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "role-lambda-execution" {
    role       = "${aws_iam_role.bitbucket_listener.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "role-lambda-ssm" {
    role       = "${aws_iam_role.bitbucket_listener.name}"
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "role-apigatway-sqs" {
    role       = "${aws_iam_role.bitbucket_listener.name}"
    policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

/* resource "aws_route53_record" "records" {
  zone_id  = data.aws_route53_zone.public.zone_id
  name     = "bitbucket-listener-shared-${var.env_type}.${data.aws_route53_zone.public.name}"
  type     = "CNAME"
  ttl      = 300
  records  = aws_api_gateway_stage.bitbucket_listener.invoke_url
} */
