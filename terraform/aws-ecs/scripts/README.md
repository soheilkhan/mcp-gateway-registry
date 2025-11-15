# Infrastructure Automation Scripts

This directory contains utility scripts for managing, monitoring, and documenting the MCP Gateway Registry infrastructure on AWS.

## Scripts Overview

### 1. build-and-push-keycloak.sh - Docker Build & Push to ECR

Automates building a Keycloak Docker image and pushing it to AWS ECR (Elastic Container Registry).

**Quick Start:**
```bash
# Build and push with defaults (latest tag to us-west-2)
./build-and-push-keycloak.sh

# Build and push with custom tag
./build-and-push-keycloak.sh --image-tag v24.0.1

# Build only (don't push)
./build-and-push-keycloak.sh --no-push
```

**Options:**
- `--aws-region REGION` - AWS region (default: us-west-2)
- `--image-tag TAG` - Image tag (default: latest)
- `--aws-profile PROFILE` - AWS profile (default: default)
- `--dockerfile PATH` - Dockerfile path (default: docker/keycloak/Dockerfile)
- `--build-context PATH` - Build context (default: docker/keycloak)
- `--no-push` - Build only, don't push to ECR
- `--help` - Show help message

**Using with Make:**
```bash
# Build Keycloak image locally
make build-keycloak

# Build and push to ECR
make build-and-push-keycloak

# Deploy to ECS (after push)
make deploy-keycloak

# Complete workflow: build, push, and deploy
make update-keycloak AWS_REGION=us-west-2 IMAGE_TAG=v24.0.1
```

**Prerequisites:**
- Docker installed and running
- AWS CLI installed and configured
- AWS credentials with ECR access
- Permission to push to ECR repository `keycloak`

**Features:**
- Color-coded output for easy readability
- Step-by-step progress tracking
- Error handling with clear error messages
- ECR login automation
- Image verification after push

---

### 2. save-terraform-outputs.sh - Export Terraform Outputs

Exports Terraform outputs to both text and JSON formats for infrastructure documentation.

**Quick Start:**
```bash
# Save outputs in default text format
./save-terraform-outputs.sh

# Save outputs as JSON
./save-terraform-outputs.sh --json
```

**Options:**
- `--output-file FILE` - Output file path (default: terraform-outputs.txt)
- `--terraform-dir DIR` - Terraform directory (default: aws-ecs)
- `--json` - Save output in JSON format instead of text
- `--no-backup` - Don't create backup of previous output
- `--help` - Show help message

**Using with Make:**
```bash
# Save outputs to text file
make save-outputs

# Save outputs to JSON file
make save-outputs-json
```

**Features:**
- Always exports JSON to `terraform-outputs.json`
- Creates timestamped backups of previous outputs
- Formatted text output with service URLs and resource information
- Verifies Terraform directory exists before running
- Shows file size and line count after export

**Output Files Generated:**
- `terraform-outputs.txt` - Human-readable formatted output
- `terraform-outputs.json` - Machine-readable JSON format (used by other scripts)
- `terraform-outputs.txt.backup-TIMESTAMP` - Backup of previous text output
- `terraform-outputs.json.backup-TIMESTAMP` - Backup of previous JSON output

---

### 3. view-cloudwatch-logs.sh - View CloudWatch Logs

Displays CloudWatch logs for ECS services with support for live tailing and filtering.

**Quick Start:**
```bash
# View logs from all components (last 30 minutes)
./view-cloudwatch-logs.sh

# View Keycloak logs with live tailing
./view-cloudwatch-logs.sh --component keycloak --follow

# View registry logs from last 5 minutes
./view-cloudwatch-logs.sh --component registry --minutes 5

# View logs matching a pattern
./view-cloudwatch-logs.sh --filter "ERROR"
```

**Options:**
- `--minutes N` - Number of minutes to look back (default: 30)
- `--follow` - Follow logs in real-time (like `tail -f`)
- `--component COMP` - View logs for specific component:
  - `keycloak` - Keycloak authentication service
  - `registry` - MCP Gateway Registry
  - `auth-server` - MCP Gateway Auth Server
  - `all` - All components (default)
- `--start-time TIME` - Start time (format: 2024-01-15T10:00:00Z)
- `--end-time TIME` - End time (format: 2024-01-15T10:30:00Z)
- `--filter PATTERN` - Filter logs by pattern (regex)
- `--help` - Show help message

**Using with Make:**
```bash
# View all logs from last 30 minutes
make view-logs

# View Keycloak logs
make view-logs-keycloak

# View Registry logs
make view-logs-registry

# View Auth Server logs
make view-logs-auth

# Follow logs in real-time
make view-logs-follow
```

**Dependencies:**
- AWS CLI installed and configured
- AWS credentials with CloudWatch Logs read access
- Terraform outputs file (run `save-terraform-outputs.sh` first)

**Features:**
- Displays logs from multiple services with clear component labels
- Real-time log tailing support with `--follow` flag
- Timestamp conversion from Unix milliseconds to readable format
- Component-based filtering
- Pattern-based log filtering
- Color-coded output for easy reading
- Automatic log group detection and validation

**Log Groups Monitored:**
- `/ecs/keycloak` - Keycloak service logs
- `/ecs/mcp-gateway-registry` - Registry service logs
- `/ecs/mcp-gateway-auth-server` - Auth server service logs
- `/aws/alb` - Application Load Balancer logs

---

## Workflow Examples

### Complete Keycloak Deployment

```bash
# 1. Build and push the Docker image
make build-and-push-keycloak IMAGE_TAG=v24.0.1

# 2. Deploy to ECS
make deploy-keycloak

# 3. Save infrastructure documentation
make save-outputs

# 4. Monitor deployment with live logs
make view-logs-follow
```

### Troubleshooting Service Issues

```bash
# 1. View recent logs for a specific service
make view-logs-keycloak

# 2. Follow logs in real-time while reproducing issue
make view-logs-follow

# 3. Filter logs for errors
./view-cloudwatch-logs.sh --filter "ERROR" --minutes 60

# 4. Export current infrastructure state
make save-outputs-json
```

### Scheduled Infrastructure Documentation

```bash
# Update infrastructure documentation weekly
make save-outputs

# Archive the outputs
cp terraform/aws-ecs/terraform-outputs.txt infrastructure-docs/$(date +%Y-%m-%d)-outputs.txt
cp terraform/aws-ecs/terraform-outputs.json infrastructure-docs/$(date +%Y-%m-%d)-outputs.json
```

---

## Prerequisites

All scripts require:
- Bash 4.0 or higher
- AWS CLI v2 installed and configured
- AWS credentials with appropriate permissions
- Access to the Terraform working directory

### AWS IAM Permissions Required

**For build-and-push-keycloak.sh:**
- `ecr:GetAuthorizationToken`
- `ecr:DescribeRepositories`
- `ecr:CreateRepository`
- `ecr:PutImage`
- `ecr:DescribeImages`

**For view-cloudwatch-logs.sh:**
- `logs:DescribeLogGroups`
- `logs:FilterLogEvents`
- `logs:DescribeLogStreams`

**For save-terraform-outputs.sh:**
- Read access to Terraform state files
- `terraform` CLI access

---

## Common Issues and Solutions

### "AWS CLI is not installed or not in PATH"
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### "Failed to login to ECR"
```bash
# Verify ECR permissions
aws ecr describe-repositories --repository-names keycloak

# Check AWS credentials
aws sts get-caller-identity
```

### "Terraform outputs file not found"
```bash
# Generate the outputs file first
./save-terraform-outputs.sh
```

### "Failed to create output file"
```bash
# Check directory permissions
ls -la terraform/aws-ecs/

# Ensure terraform is initialized
cd terraform/aws-ecs && terraform init
```

---

## Best Practices

1. **Always save outputs before deploying:**
   ```bash
   make save-outputs
   ```

2. **Run builds with specific tags, not 'latest':**
   ```bash
   make build-and-push-keycloak IMAGE_TAG=v24.0.1
   ```

3. **Review logs before and after changes:**
   ```bash
   make view-logs-follow
   ```

4. **Keep outputs backed up:**
   - The scripts automatically create timestamped backups
   - Archive outputs to version control periodically

5. **Test scripts locally before using in CI/CD:**
   ```bash
   ./terraform/aws-ecs/scripts/view-cloudwatch-logs.sh --help
   ```

---

## Further Reading

- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [AWS CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [ECS Service Updates](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/update-service.html)
