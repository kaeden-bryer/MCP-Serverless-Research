# MCP Serverless Research — Execution Plan

## Project Goal

Compare **serverless (AWS Lambda)** vs **server-based (AWS EC2)** hosting for an MCP (Model Context Protocol) server. The same Docker image is deployed to both targets so that infrastructure is the only variable.

Three collaborators: the repo owner, **Natalie**, and **Landon**.

---

## Architecture Decisions (Confirmed)

| Decision | Choice | Rationale |
|---|---|---|
| Language | Python | Team preference |
| MCP framework | Official `mcp` Python SDK (FastMCP) | Real MCP protocol, will be extended later |
| Server transport | SSE (Server-Sent Events) | Required for HTTP-based MCP; works on EC2 |
| Lambda approach | Standard Lambda + Lambda Web Adapter | Same image runs on both targets; SSE limitations surface as a research finding |
| IaC | Terraform + HCP Terraform | Remote state, locking, free tier for small teams |
| Environment isolation | Terraform workspaces (one per branch) | Isolated per-person deployments without separate accounts |
| CI/CD | GitHub Actions | Push = deploy, PR close = destroy, merge = production |
| AWS region | `us-east-2` | Team preference |
| ECR | One shared repo, tags per commit SHA | Bootstrapped once by admin via CLI |

---

## Architecture Overview

```
GitHub repo (code + Terraform)
    │
    ├── mcp-server/          # MCP server app + Dockerfile
    ├── terraform/           # IaC for Lambda and EC2
    └── .github/workflows/   # CI/CD pipelines
            │
            ▼
    Push branch → GitHub Actions:
        1. Build Docker image
        2. Push to shared ECR (tagged with commit SHA)
        3. terraform apply in per-branch workspace
        4. Comment Lambda URL + EC2 IP on PR
            │
    Merge to main → promote to "production" workspace
    Close PR      → terraform destroy + delete workspace (cost control)
```

---

## Project Structure

```
MCP-Serverless-Research/
├── CLAUDE.md                          # This file
├── brainstorming.md                   # Original planning conversation
├── .gitignore
├── mcp-server/
│   ├── server.py                      # MCP server (FastMCP, hello tool stub)
│   ├── requirements.txt
│   └── Dockerfile
├── terraform/
│   ├── backend.tf                     # HCP Terraform remote state
│   ├── variables.tf                   # aws_region, deployer_name, ecr_repository_url, image_tag
│   ├── main.tf                        # AWS provider
│   ├── lambda.tf                      # Lambda function + IAM role + Function URL
│   ├── ec2.tf                         # EC2 instance + security group + IAM instance profile
│   └── outputs.tf                     # Lambda URL, EC2 IP
└── .github/
    └── workflows/
        ├── deploy.yml                 # Push to branch → deploy preview env
        ├── destroy.yml                # PR closed → tear down + delete workspace
        └── promote.yml                # Merge to main → production deploy
```

---

## Known Limitation: Lambda + SSE

MCP's SSE transport requires a **persistent HTTP connection** that stays open while the server streams responses. Standard AWS Lambda terminates after the response is sent, which conflicts with SSE's long-lived connection model.

The **Lambda Web Adapter** (bundled in the Dockerfile) allows the same container to start on Lambda and receive HTTP requests. However, SSE sessions will be cut off when Lambda's response completes or times out. This is expected and is itself a research finding — the comparison will surface exactly how this plays out in practice.

---

## Implementation Phases

### Phase 1: MCP Server Stub ✅ (in repo)

- `mcp-server/server.py`: FastMCP server with one `hello` tool
- `mcp-server/requirements.txt`: `mcp[cli]`
- `mcp-server/Dockerfile`: Python 3.12-slim, Lambda Web Adapter included, port 8080

### Phase 2: Terraform — Lambda

- `terraform/lambda.tf`: Lambda function (container image) + IAM role + Function URL
- `terraform/backend.tf`: HCP Terraform remote state config
- `terraform/variables.tf`: Input variables
- `terraform/main.tf`: AWS provider

### Phase 3: Terraform — EC2

- `terraform/ec2.tf`: EC2 `t3.micro` + security group (port 8080) + IAM instance profile for ECR pull
- EC2 uses `user_data` to install Docker and start the container on boot
- Uses Amazon Linux 2023

### Phase 4: Terraform — Outputs

- `terraform/outputs.tf`: Lambda Function URL, EC2 public IP

### Phase 5: GitHub Actions Workflows

| Workflow | Trigger | Action |
|---|---|---|
| `deploy.yml` | Push to any branch except `main` | Build → push ECR → terraform apply → comment PR |
| `destroy.yml` | PR closed (merged or manual) | terraform destroy → delete workspace |
| `promote.yml` | Push to `main` | Retag image as `latest` → terraform apply on `production` workspace |

Branch name → Terraform workspace name (sanitized: `/` and `_` → `-`, lowercased).
Image tag = commit SHA (immutable and traceable).

---

## One-Time Setup (Admin Does This Before Anyone Else)

These steps are done once when starting the project. The admin shares the resulting credentials with each team member.

---

### Step 1: Create an AWS Account

1. Go to [https://aws.amazon.com](https://aws.amazon.com) → **Create an AWS Account**
2. Enter an email address, account name, payment info
3. Choose the **Free Tier** — EC2 `t3.micro` and Lambda are both included

---

### Step 2: Create IAM Users (One Per Person)

From the AWS Console:

1. Search **IAM** in the top search bar → open IAM
2. Left sidebar → **Users** → **Create user**
3. Create three users: `natalie`, `landon`, `[your-name]`
4. For each user:
   - **Step 1**: Enter username
   - **Step 2**: Attach policies → search and attach `PowerUserAccess`
   - **Step 3**: Review and create
5. After creating each user: click the user → **Security credentials** tab → **Create access key** → choose **CLI** use case → save the `Access Key ID` and `Secret Access Key`
   - Each person saves ONLY their own keys — never share or commit these

> **Why `PowerUserAccess`?** It grants access to EC2, Lambda, ECR, and IAM role creation, without full administrator rights.

---

### Step 3: Bootstrap the Shared ECR Repository

Run this once from your local machine (with your IAM credentials configured):

```bash
# Configure your local AWS CLI with your IAM credentials
aws configure
# Enter: Access Key ID, Secret Access Key, region: us-east-2, output: json

# Create the shared ECR repository
aws ecr create-repository \
  --repository-name mcp-server \
  --region us-east-2

# The output will contain the repository URI, e.g.:
# "repositoryUri": "123456789012.dkr.ecr.us-east-2.amazonaws.com/mcp-server"
# Save this URI — you'll need it in Step 6
```

---

### Step 4: Set Up HCP Terraform

1. Go to [https://app.terraform.io](https://app.terraform.io) → **Create account** (free)
2. Create an **Organization** (e.g. `mcp-comparison-team`)
3. Invite Natalie and Landon: **Organization Settings** → **Users** → **Invite a user**
4. Generate a team token: **Organization Settings** → **API Tokens** → **Create a team token**
   - Save this token as `TF_API_TOKEN` — you'll add it to GitHub in the next step

5. Open `terraform/backend.tf` in this repo and replace `YOUR_HCP_ORG_NAME` with your actual organization name, then commit and push.

---

### Step 5: Add GitHub Repository Secrets

In this GitHub repo: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these four secrets:

| Secret Name | Value | Where to find it |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Your IAM access key | Step 2 above |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret key | Step 2 above |
| `TF_API_TOKEN` | HCP Terraform team token | Step 4 above |

> These are shared repo-level secrets. All team members benefit from them without ever seeing the raw values.

---

### Step 6: Each Person Installs the AWS CLI

Each team member does this on their own machine:

```bash
# macOS
brew install awscli

# Windows (in PowerShell)
winget install Amazon.AWSCLI

# Verify
aws --version
```

Then configure with their own IAM credentials:

```bash
aws configure
# AWS Access Key ID: [your personal key from Step 2]
# AWS Secret Access Key: [your personal secret from Step 2]
# Default region name: us-east-2
# Default output format: json
```

---

### Step 7: Install Terraform (Each Person)

```bash
# macOS
brew tap hashicorp/tap && brew install hashicorp/tap/terraform

# Windows
winget install Hashicorp.Terraform

# Verify
terraform --version
```

Log in to HCP Terraform:

```bash
terraform login
# This opens a browser — authenticate with your HCP account
```

---

## Day-to-Day Collaboration Workflow

Once setup is complete, the team workflow is:

```
1. git checkout -b your-name/your-feature
2. Make changes to mcp-server/ or terraform/
3. git push origin your-name/your-feature
   → GitHub Actions automatically:
      - Builds the Docker image
      - Pushes to ECR with your commit SHA as the tag
      - Runs terraform apply in a workspace named after your branch
      - Comments the Lambda URL + EC2 IP on your PR
4. Open a Pull Request when ready for review
5. When PR is merged → production workspace updates automatically
6. When PR is closed → your preview environment is destroyed automatically
```

No `docker build`, `docker push`, or `terraform apply` commands needed locally.

---

## Key Rules

- **Never commit** AWS credentials, `.tfvars` files with secrets, or `.terraform/` directories
- Each person uses their **own Terraform workspace** — never touch a teammate's workspace
- Image tags use **commit SHAs** (not branch names) for immutability and traceability
- EC2 instances cost money even when idle — the `destroy.yml` workflow handles cleanup on PR close
- The ECR repository is shared — **do not delete it** outside of the admin bootstrapping process

---

## Collaboration Model Reference

| Concern | Solution |
|---|---|
| Terraform state | HCP Terraform remote state (not local files) |
| State locking | HCP built-in (prevents simultaneous applies) |
| Environment isolation | Terraform workspaces (one per branch) |
| Deployment automation | GitHub Actions (push = deploy, PR close = destroy) |
| Image storage | One shared ECR repo, tags per commit SHA |
| Resource namespacing | `deployer_name` variable appended to all resource names |
| Secrets | GitHub repository secrets (never committed to git) |
