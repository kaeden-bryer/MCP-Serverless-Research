# IAM role that allows the EC2 instance to pull images from ECR.
# Without this, the instance would need hardcoded AWS credentials.
resource "aws_iam_role" "ec2_exec" {
  name = "ec2-exec-${var.deployer_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ecr" {
  role       = aws_iam_role.ec2_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Instance profile is the mechanism that attaches an IAM role to an EC2 instance.
resource "aws_iam_instance_profile" "ec2_exec" {
  name = "ec2-exec-${var.deployer_name}"
  role = aws_iam_role.ec2_exec.name
}

# Look up the latest Amazon Linux 2023 AMI automatically.
# AL2023 is the current recommended AWS Linux distribution.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Firewall rules for the EC2 instance.
resource "aws_security_group" "mcp_server" {
  name        = "mcp-server-sg-${var.deployer_name}"
  description = "Allow MCP server traffic on port 8080"

  ingress {
    description = "MCP server port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound so the instance can reach ECR, AWS APIs, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "mcp_server" {
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_exec.name

  vpc_security_group_ids = [aws_security_group.mcp_server.id]

  # user_data runs as a shell script on first boot only.
  # It installs Docker, authenticates to ECR using the instance role,
  # then pulls and starts the MCP server container.
  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y docker
    systemctl start docker
    systemctl enable docker

    # Authenticate to ECR using the attached IAM role (no hardcoded credentials)
    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin ${var.ecr_repository_url}

    docker pull ${var.ecr_repository_url}:${var.image_tag}
    docker run -d -p 8080:8080 ${var.ecr_repository_url}:${var.image_tag}
  EOF

  tags = {
    Name    = "mcp-server-${var.deployer_name}"
    Owner   = var.deployer_name
    Project = "mcp-comparison"
  }
}
