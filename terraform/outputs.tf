output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.mcp_server.function_name
}

output "lambda_function_url" {
  description = "Public HTTPS URL for the Lambda MCP server"
  value       = aws_lambda_function_url.mcp_server.function_url
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 MCP server. Access via http://<ip>:8080"
  value       = aws_instance.mcp_server.public_ip
}
