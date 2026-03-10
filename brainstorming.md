# Collaborating on AWS MCP server deployment with Terraform

**human** (Mar 9, 2026, 04:09 PM)

I'm working on a project with 2 other group members. We want to compare the use of server and serverless MCP server options. To do this, we want to containerize the MCP server file in a docker image, push it to Elastic Container Registry, and then run that docker image on both AWS Lambda and AWS EC2. This way, everything is the same, except for where each image is hosted.

However, none of us have used AWS, much less collaborated on a project that uses it. I want to use Terraform and Terraform HCP to make collaboration easier. In addition, I think we should have a "Shared project" in AWS somehow, but I'm not sure what that would look like. Please suggest the best way for us to collaborate on this project, and then walk through an example where Natalie makes changes to the MCP server, and Landon wants to recreate Natalie's environment and have all of her changes.

**assistant** (Mar 9, 2026, 04:11 PM)

 I'll think through this carefully before giving you a recommendation, since the AWS/Terraform collaboration setup has several moving parts.

## The Core Problem You're Solving

When 3 people collaborate on cloud infrastructure, you face these challenges:
1. **State management** — Terraform tracks what it has deployed in a "state file." If everyone has their own local state file, you'll conflict and overwrite each other's work.
2. **Credential sharing** — You need AWS access without sharing one person's login.
3. **Environment isolation** — You each want to be able to experiment without breaking others.
4. **Code sharing** — Standard git, but infrastructure code has extra considerations.

---

## Recommended Architecture

Here's what I suggest:

### 1. One Shared AWS Account (with IAM Users per person)
Rather than each person having their own AWS account, use **one shared AWS account** where:
- One person creates the account (the "admin")
- The admin creates **IAM Users** for each teammate (Natalie, Landon, you)
- Each person gets their own AWS credentials (Access Key + Secret Key) that you never share or commit to git
- The account holds your shared resources: **ECR registry, S3 bucket for Terraform state**

This mirrors how real teams work — one company account, individual logins.

### 2. Terraform HCP (HashiCorp Cloud Platform) for State
Terraform's state file is the record of "what is deployed." HCP Terraform gives you:
- **Remote state** stored in the cloud (not on someone's laptop)
- **State locking** — prevents two people from running `terraform apply` simultaneously
- A free tier that's perfect for small teams

### 3. Git (GitHub) for Code
All your `.tf` files and MCP server code live in a shared GitHub repo. This is standard — but the key rule is: **never commit `.tfvars` files containing secrets or AWS credentials.**

### 4. Workspaces for Environment Isolation
Terraform **workspaces** let each person have their own isolated deployment (their own Lambda, EC2, etc.) without interfering with others. Think of it like git branches, but for deployed infrastructure.

---

## The Walkthrough: Natalie Makes Changes, Landon Recreates Them

Let me walk through exactly how this works end-to-end.

```
Project Structure:
├── mcp-server/
│   ├── server.py          # The MCP server code
│   └── Dockerfile         # How to containerize it
├── terraform/
│   ├── main.tf            # Core infrastructure
│   ├── variables.tf       # Input variable declarations
│   ├── outputs.tf         # What Terraform "returns" after deploying
│   ├── ecr.tf             # ECR registry definition
│   ├── lambda.tf          # Lambda deployment
│   ├── ec2.tf             # EC2 deployment
│   └── backend.tf         # Points to HCP Terraform for remote state
└── .github/
    └── workflows/
        └── deploy.yml     # (Optional) CI/CD pipeline
```

---

### Step 1: One-Time Setup (The Admin Does This)

**In AWS Console:**
```
1. Create AWS Account
2. Go to IAM → Create Users for: natalie, landon, [you]
3. Attach policy: PowerUserAccess (enough for EC2, Lambda, ECR)
4. Each user generates an Access Key — everyone saves their OWN keys locally
5. Create an S3 bucket: "mcp-project-tf-state" (for backup, HCP is primary)
6. Create an ECR repository: "mcp-server"
```

**In HCP Terraform (app.terraform.io):**
```
1. Create a free organization, e.g. "mcp-comparison-team"
2. Create a Project → "mcp-server"
3. Invite Natalie and Landon to the organization
4. Generate an HCP Team Token (shared) — this is what terraform uses to auth
   with HCP, not individual tokens
```

**Why HCP instead of just S3 for state?**
S3 can store state files, but HCP adds state *locking* (prevents simultaneous applies) and a visual UI showing your deployment history. Both work; HCP is easier for beginners collaborating.

---

### Step 2: The Terraform Code

**`terraform/backend.tf`** — This is the key collaboration file. It tells Terraform "store our state in HCP, not locally."

```hcl
# backend.tf
# This file tells Terraform WHERE to store its state file.
# Instead of a local terraform.tfstate file, it lives in HCP cloud.
# Everyone on the team points to the SAME organization/project here.

terraform {
  cloud {
    organization = "mcp-comparison-team"  # Your HCP org name

    workspaces {
      # "tags" mode means each person can create their own workspace
      # by running: terraform workspace new natalie
      # This gives everyone an isolated environment
      tags = ["mcp-server"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**`terraform/variables.tf`** — Declare inputs so each person can customize without editing shared code:

```hcl
# variables.tf
# Think of these like function parameters — they let each person
# pass in their own values without editing the shared .tf files.

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "deployer_name" {
  description = "Your name — used to tag and namespace resources"
  type        = string
  # No default: each person MUST provide this
}

variable "ecr_repository_url" {
  description = "The URL of the shared ECR repository"
  type        = string
}

variable "image_tag" {
  description = "The Docker image tag to deploy (e.g., natalie-feature-x)"
  type        = string
  default     = "latest"
}
```

**`terraform/ecr.tf`** — The ECR registry is **shared** (one repo, many image tags):

```hcl
# ecr.tf
# ECR (Elastic Container Registry) is like DockerHub, but private in AWS.
# We create ONE registry that everyone pushes their images to.
# Each person uses a different image TAG to identify their version.
# e.g., natalie-v1, landon-test, latest

resource "aws_ecr_repository" "mcp_server" {
  name                 = "mcp-server"
  image_tag_mutability = "MUTABLE"  # Allows overwriting tags (convenient for dev)

  image_scanning_configuration {
    scan_on_push = true  # AWS scans for known vulnerabilities on each push
  }

  tags = {
    Project = "mcp-comparison"
  }
}

output "ecr_repository_url" {
  description = "Use this URL when running 'docker push'"
  value       = aws_ecr_repository.mcp_server.repository_url
}
```

**`terraform/lambda.tf`** — Lambda deployment (serverless MCP):

```hcl
# lambda.tf
# AWS Lambda runs your container without you managing a server.
# It spins up on-demand and shuts down when idle.

# IAM Role: Lambda needs permission to run and write logs
# Think of this as "what is Lambda allowed to do?"
resource "aws_iam_role" "lambda_exec" {
  # Each person's role gets their name to avoid conflicts
  name = "lambda-exec-${var.deployer_name}"

  # "Assume role policy" = who is allowed to USE this role
  # Here we're saying: Lambda functions may use this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attach AWS's pre-built policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "mcp_server" {
  function_name = "mcp-server-${var.deployer_name}"  # e.g., mcp-server-natalie
  role          = aws_iam_role.lambda_exec.arn

  # This tells Lambda to use a container image (not a zip file)
  package_type = "Image"
  image_uri    = "${var.ecr_repository_url}:${var.image_tag}"

  # Lambda resource limits
  timeout      = 30   # seconds before Lambda kills the function
  memory_size  = 512  # MB of RAM

  tags = {
    Owner   = var.deployer_name
    Project = "mcp-comparison"
  }
}

output "lambda_function_name" {
  value = aws_lambda_function.mcp_server.function_name
}
```

**`terraform/ec2.tf`** — EC2 deployment (traditional server MCP):

```hcl
# ec2.tf
# EC2 is a virtual machine that runs 24/7.
# We run our Docker container on it using "user_data" — a startup script
# that runs automatically when the instance first boots.

# Find the latest Amazon Linux 2 AMI automatically
# (AMI = Amazon Machine Image, the OS template for the VM)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Security group = firewall rules for the EC2 instance
resource "aws_security_group" "mcp_server" {
  name        = "mcp-server-sg-${var.deployer_name}"
  description = "Allow MCP server traffic"

  # Allow inbound on port 8080 (where MCP server listens)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # In production you'd restrict this!
  }

  # Allow all outbound (so the server can call external APIs, pull images, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "mcp_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"  # Cheapest general-purpose instance

  vpc_security_group_ids = [aws_security_group.mcp_server.id]

  # user_data runs as a shell script on first boot
  # This installs Docker and starts your container automatically
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    service docker start

    # Log in to ECR (AWS's private Docker registry)
    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin ${var.ecr_repository_url}

    # Pull and run the MCP server container
    docker pull ${var.ecr_repository_url}:${var.image_tag}
    docker run -d -p 8080:8080 ${var.ecr_repository_url}:${var.image_tag}
  EOF

  tags = {
    Name    = "mcp-server-${var.deployer_name}"
    Owner   = var.deployer_name
    Project = "mcp-comparison"
  }
}

output "ec2_public_ip" {
  description = "SSH or send requests to this IP"
  value       = aws_instance.mcp_server.public_ip
}
```

---

### Step 3: The Natalie → Landon Workflow

Now the concrete walkthrough you asked for:

**Natalie makes changes:**

```bash
# 1. Natalie pulls latest code from GitHub
git checkout main && git pull

# 2. She creates a feature branch
git checkout -b feature/add-tool-endpoint

# 3. She edits mcp-server/server.py, adds a new tool, then builds her image
cd mcp-server
docker build -t mcp-server:natalie-feature-x .

# 4. She pushes to the SHARED ECR
# First, get the ECR URL (from terraform output or AWS console)
ECR_URL="123456789.dkr.ecr.us-east-1.amazonaws.com/mcp-server"

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URL

# Tag and push — the tag "natalie-feature-x" identifies HER version
docker tag mcp-server:natalie-feature-x $ECR_URL:natalie-feature-x
docker push $ECR_URL:natalie-feature-x

# 5. She deploys HER infrastructure using HER workspace
cd ../terraform
terraform workspace new natalie  # or: terraform workspace select natalie
terraform apply \
  -var="deployer_name=natalie" \
  -var="ecr_repository_url=$ECR_URL" \
  -var="image_tag=natalie-feature-x"

# 6. She pushes her code to GitHub
git add mcp-server/server.py
git commit -m "feat: add new MCP tool endpoint"
git push origin feature/add-tool-endpoint

# 7. She opens a Pull Request on GitHub, notes her image tag: natalie-feature-x
```

**Landon recreates Natalie's environment:**

```bash
# 1. Landon fetches and checks out Natalie's branch
git fetch origin
git checkout feature/add-tool-endpoint

# 2. He creates HIS OWN workspace — this is key!
# He's not touching Natalie's deployment. He's deploying the SAME code
# but into his own isolated Lambda + EC2 instances.
cd terraform
terraform workspace new landon  # Creates fresh state for Landon

# 3. He deploys using Natalie's image tag
# This pulls the EXACT same Docker image Natalie pushed to ECR
terraform apply \
  -var="deployer_name=landon" \
  -var="ecr_repository_url=$ECR_URL" \
  -var="image_tag=natalie-feature-x"  # <-- same image Natalie pushed!

# Terraform creates:
# - lambda function named "mcp-server-landon" running natalie's image
# - EC2 instance tagged "mcp-server-landon" running natalie's image
# Natalie's resources are UNTOUCHED.

# 4. Landon verifies everything works, then destroys when done
terraform destroy \
  -var="deployer_name=landon" \
  -var="ecr_repository_url=$ECR_URL" \
  -var="image_tag=natalie-feature-x"
```

---

## Key Mental Models to Remember

**Why workspaces instead of separate `.tf` files per person?**
Workspaces give each person their own state file within the same HCP project. It's like git branches for *deployed infrastructure* — same code, different deployment instances.

**Why one ECR repository with different tags?**
ECR repos are like filing cabinets; image tags are like folder labels inside them. You pay per GB stored, not per tag. It's far cheaper and simpler to have one repo with tags like `natalie-feature-x`, `landon-test`, `latest` than three separate repos.

**Why is `var.deployer_name` threaded through everything?**
Without it, if Natalie and Landon both deploy, they'd create a Lambda function both named `mcp-server` — AWS would throw a conflict error. Namespacing with the person's name makes every resource unique.

**The golden rule: never commit secrets.**
AWS credentials, HCP tokens — these go in environment variables or `~/.aws/credentials`, never in `.tf` files or git. Add `*.tfvars` and `.terraform/` to your `.gitignore`.

**human** (Mar 9, 2026, 04:20 PM)

Could this be simplified further with GitHub actions or a stronger CI/CD workflow? I want to make this as easy as possible for the others to work together

**assistant** (Mar 9, 2026, 04:21 PM)

 Great question — yes, significantly. Let me show you what a strong CI/CD setup looks like and why it simplifies things.

## The Core Idea: Replace Manual Commands with Automated Pipelines

Right now, the workflow requires each person to:
1. Manually run `docker build` + `docker push`
2. Manually run `terraform apply` with the right variables
3. Remember the right image tags, workspace names, etc.

With GitHub Actions, **a git push is the only command anyone needs to run.** The pipeline handles everything else automatically.

---

## The Simplified Mental Model

```
Developer pushes code to GitHub
        ↓
GitHub Actions detects the push
        ↓
    ┌───────────────────────────────┐
    │  1. Build Docker image        │
    │  2. Push to ECR               │
    │  3. Run terraform apply       │
    └───────────────────────────────┘
        ↓
Infrastructure is live
```

The branch name becomes the workspace name and image tag automatically — no one has to remember or type them.

---

## What Changes in the Project Structure

```
├── mcp-server/
│   ├── server.py
│   └── Dockerfile
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── ecr.tf
│   ├── lambda.tf
│   ├── ec2.tf
│   └── backend.tf
└── .github/
    └── workflows/
        ├── deploy.yml       # Runs on push to any branch → deploy preview env
        ├── destroy.yml      # Runs when a PR is closed → tear down env
        └── promote.yml      # Runs on merge to main → deploy "production"
```

The Terraform files stay almost identical. Everything new lives in `.github/workflows/`.

---

## The Three Workflows

### 1. `deploy.yml` — Deploy on Every Push

```yaml
# .github/workflows/deploy.yml
#
# CONCEPT: GitHub Actions workflows are triggered by "events" (push, PR, etc.)
# and run a series of "steps" inside a clean virtual machine.
# Each run is isolated — no leftover state from previous runs.

name: Deploy Preview Environment

on:
  push:
    branches-ignore:
      - main  # main has its own workflow (promote.yml)

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: mcp-server
  TF_CLOUD_ORGANIZATION: mcp-comparison-team

jobs:
  deploy:
    name: Build & Deploy
    runs-on: ubuntu-latest  # Fresh Ubuntu VM for every run

    steps:
      # Step 1: Check out the code that was just pushed
      - name: Checkout code
        uses: actions/checkout@v4

      # Step 2: Derive a clean workspace name from the branch name.
      # CONCEPT: Branch names can contain slashes (feature/add-tool),
      # but Terraform workspace names can't. We sanitize it here.
      # github.ref_name is the branch name, e.g. "feature/natalie-new-tool"
      # We replace "/" and "_" with "-" → "feature-natalie-new-tool"
      - name: Derive workspace name from branch
        id: workspace
        run: |
          WORKSPACE=$(echo "${{ github.ref_name }}" | sed 's/[/_]/-/g' | tr '[:upper:]' '[:lower:]')
          echo "name=$WORKSPACE" >> $GITHUB_OUTPUT
          # CONCEPT: GITHUB_OUTPUT lets you pass values between steps.
          # steps.workspace.outputs.name will equal "feature-natalie-new-tool"

      # Step 3: Configure AWS credentials from GitHub Secrets
      # CONCEPT: GitHub Secrets are encrypted env vars stored in your repo
      # settings. Nobody can read them — not even repo members.
      # You add them once at Settings → Secrets and variables → Actions.
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      # Step 4: Log in to ECR so docker can push to it
      - name: Log in to Amazon ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      # Step 5: Build and push the Docker image
      # CONCEPT: We tag the image with the commit SHA (github.sha).
      # This is better than using the branch name as a tag because:
      # - Every commit gets a unique, immutable tag
      # - You can always trace exactly which code is running
      # - Two pushes to the same branch don't overwrite each other
      - name: Build and push Docker image
        id: build
        env:
          ECR_REGISTRY: ${{ steps.ecr-login.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG ./mcp-server
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          echo "image_uri=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

      # Step 6: Install Terraform in the VM
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}
          # This token is what authenticates to HCP Terraform.
          # Without it, terraform can't read/write remote state.

      # Step 7: terraform init — downloads providers and connects to HCP
      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      # Step 8: Select or create the workspace for this branch
      # CONCEPT: "|| terraform workspace new" means:
      # "try to select the workspace; if it doesn't exist yet, create it"
      # This makes the step idempotent — safe to run multiple times
      - name: Select or create Terraform workspace
        working-directory: terraform
        run: |
          terraform workspace select ${{ steps.workspace.outputs.name }} \
            || terraform workspace new ${{ steps.workspace.outputs.name }}

      # Step 9: terraform apply — deploy the infrastructure
      # -auto-approve skips the interactive "yes/no" prompt
      # (safe in CI because a human approved the code via PR)
      - name: Terraform Apply
        working-directory: terraform
        run: |
          terraform apply -auto-approve \
            -var="deployer_name=${{ steps.workspace.outputs.name }}" \
            -var="ecr_repository_url=${{ steps.build.outputs.image_uri }}" \
            -var="image_tag=${{ github.sha }}"

      # Step 10: Post the deployment URLs as a PR comment
      # This is quality-of-life: no one has to dig through logs to find
      # where their environment was deployed
      - name: Get deployment outputs
        id: tf-output
        working-directory: terraform
        run: |
          echo "lambda=$(terraform output -raw lambda_function_name)" >> $GITHUB_OUTPUT
          echo "ec2_ip=$(terraform output -raw ec2_public_ip)" >> $GITHUB_OUTPUT

      - name: Comment deployment URLs on PR
        uses: actions/github-script@v7
        with:
          script: |
            const { data: prs } = await github.rest.pulls.list({
              owner: context.repo.owner,
              repo: context.repo.repo,
              head: `${context.repo.owner}:${context.ref.replace('refs/heads/', '')}`,
              state: 'open'
            });
            if (prs.length > 0) {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: prs[0].number,
                body: `## 🚀 Preview Environment Deployed
                
            | Resource | Value |
            |----------|-------|
            | Lambda Function | \`${{ steps.tf-output.outputs.lambda }}\` |
            | EC2 IP | \`${{ steps.tf-output.outputs.ec2_ip }}\` |
            | Image Tag | \`${{ github.sha }}\` |
            | Workspace | \`${{ steps.workspace.outputs.name }}\` |
            
            _Deployed from commit ${{ github.sha }}_`
              });
            }
```

---

### 2. `destroy.yml` — Tear Down When PR is Closed

```yaml
# .github/workflows/destroy.yml
#
# CONCEPT: This is important for cost control. EC2 instances cost money
# even when idle. When a PR is merged or closed, we automatically
# destroy the preview environment so you're not paying for it.

name: Destroy Preview Environment

on:
  pull_request:
    types: [closed]  # Triggers on both merge AND manual close

env:
  AWS_REGION: us-east-1
  TF_CLOUD_ORGANIZATION: mcp-comparison-team

jobs:
  destroy:
    name: Destroy Environment
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Derive workspace name
        id: workspace
        run: |
          WORKSPACE=$(echo "${{ github.head_ref }}" | sed 's/[/_]/-/g' | tr '[:upper:]' '[:lower:]')
          echo "name=$WORKSPACE" >> $GITHUB_OUTPUT

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      - name: Select workspace
        working-directory: terraform
        run: terraform workspace select ${{ steps.workspace.outputs.name }}

      # Destroy all resources in this workspace
      # We need to pass dummy vars so Terraform doesn't error on missing inputs —
      # the values don't matter since we're only destroying, not creating
      - name: Terraform Destroy
        working-directory: terraform
        run: |
          terraform destroy -auto-approve \
            -var="deployer_name=${{ steps.workspace.outputs.name }}" \
            -var="ecr_repository_url=dummy" \
            -var="image_tag=dummy"

      # CONCEPT: After destroying resources, delete the workspace itself
      # so HCP doesn't accumulate stale empty workspaces
      - name: Delete Terraform workspace
        working-directory: terraform
        run: |
          terraform workspace select default
          terraform workspace delete ${{ steps.workspace.outputs.name }}
```

---

### 3. `promote.yml` — Merge to Main = Production Deploy

```yaml
# .github/workflows/promote.yml
#
# CONCEPT: The "main" branch represents your stable, shared environment.
# When a PR is merged, this promotes that code to a permanent deployment
# that all three of you can reference for your comparison testing.

name: Deploy to Production

on:
  push:
    branches:
      - main

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: mcp-server
  TF_CLOUD_ORGANIZATION: mcp-comparison-team

jobs:
  promote:
    name: Promote to Production
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Log in to Amazon ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      # Re-tag the image as "latest" so it's easy to reference
      # CONCEPT: We pull the image that was already built and tested
      # on the feature branch — we don't rebuild it. This guarantees
      # what's in production is EXACTLY what was tested in the PR.
      - name: Retag image as latest
        env:
          ECR_REGISTRY: ${{ steps.ecr-login.outputs.registry }}
        run: |
          docker pull $ECR_REGISTRY/$ECR_REPOSITORY:${{ github.sha }}
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:${{ github.sha }} \
                     $ECR_REGISTRY/$ECR_REPOSITORY:latest
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
          echo "image_uri=$ECR_REGISTRY/$ECR_REPOSITORY:latest" >> $GITHUB_OUTPUT
        id: retag

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      # Production always uses the "production" workspace
      - name: Select production workspace
        working-directory: terraform
        run: |
          terraform workspace select production \
            || terraform workspace new production

      - name: Terraform Apply
        working-directory: terraform
        run: |
          terraform apply -auto-approve \
            -var="deployer_name=production" \
            -var="ecr_repository_url=${{ steps.retag.outputs.image_uri }}" \
            -var="image_tag=latest"
```

---

## The Simplified Natalie → Landon Workflow Now

With all of this in place, here's how collaboration actually looks:

```
Natalie:
  git checkout -b feature/new-tool
  # ... edits server.py ...
  git push origin feature/new-tool
  # Opens a Pull Request
  # GitHub Actions automatically:
  #   ✓ Builds her Docker image
  #   ✓ Pushes to ECR tagged with her commit SHA
  #   ✓ Runs terraform apply in workspace "feature-new-tool"
  #   ✓ Comments the Lambda name + EC2 IP on her PR

Landon (wants to review):
  # Sees the PR comment with deployment info
  # He can hit Natalie's already-deployed environment immediately
  # OR to deploy his own copy:
  git checkout feature/new-tool
  git checkout -b landon/review-natalie-tool
  git push origin landon/review-natalie-tool
  # GitHub Actions deploys a second isolated environment for him automatically
  # No terraform commands, no docker commands, nothing

PR gets merged to main:
  # destroy.yml tears down both preview environments (cost savings)
  # promote.yml deploys the final version to the shared "production" workspace
```

---

## The One-Time Secrets Setup

The only manual step is adding these four secrets to your GitHub repo once, at **Settings → Secrets and variables → Actions → New repository secret**:

| Secret Name | Where to get it |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM → Your user → Security credentials |
| `AWS_SECRET_ACCESS_KEY` | Same — only shown once at creation |
| `TF_API_TOKEN` | HCP Terraform → User Settings → Tokens |

These are shared repo secrets — everyone on the team benefits from them without ever seeing the raw values.

---

## Why This Is Better

The key mental shift is: **your git workflow IS your deployment workflow.** Push a branch → get an environment. Merge → get production. Close a PR → environment disappears. No one needs to remember Terraform commands, AWS CLI syntax, or image tag conventions. The pipeline encodes all of that knowledge once, and it runs reliably every time.