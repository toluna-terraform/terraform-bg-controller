# Writes received taskTokekn to SSM. 
# Also, invokes SF with taskToken from SSM param, if called from CodeBuild

data "archive_file" "appmesh_sf_task_token_zip" {
    type        = "zip"
    source_file  = "${path.module}/appmesh-sf-task-token.py"
    output_path = "${path.module}/appmesh_sf_task_token.zip"
}

resource "aws_lambda_function" "appmesh_sf_task_token" {
  runtime = "python3.9"
  function_name = "${var.app_name}-${var.env_name}-appmesh-sf-task-token"

  description = "writes taskTokekn to SSM. Also, invokes SF with taskToken if called from CodeBuild "
  filename = "${path.module}/appmesh_sf_task_token.zip"
  source_code_hash = filebase64sha256("${path.module}/appmesh_sf_task_token.zip")
  
  role = "${aws_iam_role.lambda-role.arn}"
  handler = "appmesh-sf-task-token.lambda_handler"

  environment {
    variables = {
      APP_NAME = var.app_name
      ENV_NAME = var.env_name
      ENV_TYPE = var.env_type
    }
  }

  timeout = 60
    
  kms_key_arn = "ckv_km"
  
  tracing_config {
    mode = "Active"
  }
}
