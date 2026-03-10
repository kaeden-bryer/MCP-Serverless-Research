variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-2"
}

variable "deployer_name" {
  description = "Your name — used to namespace all resources (e.g. natalie, landon). No spaces or uppercase."
  type        = string
}

variable "ecr_repository_url" {
  description = "Full URL of the shared ECR repository, e.g. 123456789012.dkr.ecr.us-east-2.amazonaws.com/mcp-server"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy. In CI this is the commit SHA; locally you can use any tag."
  type        = string
  default     = "latest"
}
