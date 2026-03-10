# IAM role that grants Lambda permission to execute and write logs.
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.deployer_name}"

  # "Assume role policy" defines who is allowed to use this role.
  # Here: only Lambda functions may assume it.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# AWS-managed policy that allows Lambda to write logs to CloudWatch.
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "mcp_server" {
  function_name = "mcp-server-${var.deployer_name}"
  role          = aws_iam_role.lambda_exec.arn

  # Run a container image rather than a zip-packaged function.
  package_type = "Image"
  image_uri    = "${var.ecr_repository_url}:${var.image_tag}"

  timeout     = 30  # seconds; Lambda kills the invocation after this
  memory_size = 512 # MB

  tags = {
    Owner   = var.deployer_name
    Project = "mcp-comparison"
  }
}

# Lambda Function URL: gives the function a public HTTPS endpoint
# without needing API Gateway.
resource "aws_lambda_function_url" "mcp_server" {
  function_name      = aws_lambda_function.mcp_server.function_name
  authorization_type = "NONE"
  invoke_mode        = "RESPONSE_STREAM"
}

# As of Oct 2025, public Function URLs require both permissions.
resource "aws_lambda_permission" "function_url_invoke" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.mcp_server.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "function_url_invoke_function" {
  statement_id  = "FunctionURLAllowPublicInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mcp_server.function_name
  principal     = "*"
}
