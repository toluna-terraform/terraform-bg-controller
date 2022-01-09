resource "aws_lambda_layer_version" "lambda_layer" {
  filename   = "${path.module}/layer/layer.zip"
  layer_name = "bitbucket_listner"

  compatible_runtimes = ["python3.8"]
}

data "archive_file" "lambda_zip" {
 type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.root}/lambda.zip"
}

resource "aws_lambda_function" "lambda" {
  filename         = "lambda.zip"
  function_name    = "${var.lambda_name}"
  role             = "${aws_iam_role.lambda_iam.arn}"
  handler          = "bitbucket_listner.lambda_handler"
  runtime          = "python3.8"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  layers = [aws_lambda_layer_version.lambda_layer.arn]
  timeout = 180
  depends_on = [
    aws_lambda_layer_version.lambda_layer
  ]
}

resource "null_resource" "remove_zip" {
  provisioner "local-exec" {
    when = create
    command = "rm -f ${path.root}/lambda.zip"
  }
  depends_on = [aws_lambda_function.lambda]
}

resource "aws_iam_role" "lambda_iam" {
  name = "role-lambda-cleanup-instances"
  assume_role_policy = "${file("${path.module}/policy.json")}"
}

resource "aws_iam_role_policy_attachment" "role-lambda-execution" {
    role       = "${aws_iam_role.lambda_iam.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "role-lambda-ssm" {
    role       = "${aws_iam_role.lambda_iam.name}"
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}
