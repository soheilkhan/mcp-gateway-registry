# ECS and ALB Logging Guide

This guide covers how to retrieve real-time and historical logs from your ECS cluster, including application logs and ALB access logs.

## Quick Start

**1. Store Terraform outputs** (run once after deployment):
```bash
./store-resources.sh
```

**2. Get logs:**
```bash
./get-ecs-logs.sh registry-logs
./get-ecs-logs.sh auth-logs --follow
./get-ecs-logs.sh keycloak-logs --minutes 60
```

## Overview

The following logging tools are available:

- **`store-resources.sh`** - Captures Terraform outputs to `.resources` file
- **`get-ecs-logs.sh`** - Bash script for quick log retrieval (reads from `.resources`)
- **`get_ecs_logs.py`** - Python CLI with more features and structured output
- **CloudWatch Logs** - Direct integration with AWS CloudWatch
- **ALB Access Logs** - Stored in S3 with AWS CLI integration

## Resource Discovery Setup

The logging scripts automatically discover ECS cluster details from your Terraform deployment:

**Step 1: Generate resource file** (after Terraform deployment):
```bash
./store-resources.sh
```

This creates `.resources` file containing:
- ECS cluster name and ARN
- CloudWatch log group names
- ALB DNS names and URLs
- VPC and networking information
- Deployment status

**Step 2: Use logging scripts**:
```bash
./get-ecs-logs.sh registry-logs
```

The scripts automatically load values from `.resources` if it exists.

**Note**: The `.resources` file is in `.gitignore` and should be regenerated after each Terraform deployment.

## Prerequisites

### For Bash Script (`get-ecs-logs.sh`)
- AWS CLI v2 installed and configured
- Appropriate AWS credentials with permissions for:
  - `logs:DescribeLogGroups`
  - `logs:DescribeLogStreams`
  - `logs:GetLogEvents`
  - `ecs:ListTasks`
  - `ecs:DescribeTasks`
  - `ecs:DescribeServices`
  - `elbv2:DescribeLoadBalancers`
  - `elbv2:DescribeLoadBalancerAttributes`
  - `s3:ListBucket`
  - `s3:GetObject`

### For Python Script (`get_ecs_logs.py`)
- Python 3.8+
- boto3 installed: `pip install boto3` or `uv add boto3`
- AWS CLI v2 installed for streaming logs
- Same AWS permissions as above

## Usage

### Bash Script

```bash
./get-ecs-logs.sh [COMMAND] [OPTIONS]
```

#### Commands

**Get ECS Task Logs**

```bash
# Get logs from all services (last 30 minutes)
./get-ecs-logs.sh ecs-logs

# Get auth service logs
./get-ecs-logs.sh auth-logs

# Get registry service logs
./get-ecs-logs.sh registry-logs

# Get keycloak service logs
./get-ecs-logs.sh keycloak-logs

# Get logs from all services with all options
./get-ecs-logs.sh all-logs --follow
```

**Get ALB Logs**

```bash
# Get registry ALB logs
./get-ecs-logs.sh alb-logs

# Get keycloak ALB logs
./get-ecs-logs.sh alb-logs --alb keycloak
```

**List Resources**

```bash
# List all running services
./get-ecs-logs.sh list-services

# List all running tasks
./get-ecs-logs.sh list-tasks
```

#### Options

| Option | Description | Example |
|--------|-------------|---------|
| `--follow` | Follow logs in real-time (like `tail -f`) | `--follow` |
| `--minutes N` | Show logs from last N minutes | `--minutes 60` |
| `--tail N` | Show last N lines | `--tail 200` |
| `--region REGION` | AWS region | `--region us-west-2` |
| `--cluster NAME` | ECS cluster name | `--cluster my-cluster` |
| `--filter TEXT` | Filter logs by text pattern | `--filter "error"` |
| `--alb NAME` | ALB name (registry or keycloak) | `--alb registry` |
| `--error-only` | Show only 4xx/5xx errors (ALB) | `--error-only` |

#### Examples

```bash
# Follow registry logs in real-time
./get-ecs-logs.sh registry-logs --follow

# Get last 60 minutes of auth logs
./get-ecs-logs.sh auth-logs --minutes 60

# Get filtered logs (search for errors)
./get-ecs-logs.sh registry-logs --filter "ERROR"

# Get ALB logs
./get-ecs-logs.sh alb-logs --alb registry

# List all services and their status
./get-ecs-logs.sh list-services

# List all running tasks
./get-ecs-logs.sh list-tasks
```

### Python Script

```bash
python3 get_ecs_logs.py [COMMAND] [OPTIONS]
```

#### Commands

**Get ECS Task Logs**

```bash
# Get logs from all services
python3 get_ecs_logs.py ecs-logs

# Get auth service logs with follow
python3 get_ecs_logs.py auth-logs --follow

# Get registry logs filtered by pattern
python3 get_ecs_logs.py registry-logs --filter "error"

# Get keycloak logs from last 60 minutes
python3 get_ecs_logs.py keycloak-logs --minutes 60

# Get logs from all services
python3 get_ecs_logs.py all-logs --follow
```

**Get ALB Logs**

```bash
# Get registry ALB logs
python3 get_ecs_logs.py alb-logs

# Get keycloak ALB logs
python3 get_ecs_logs.py alb-logs --alb keycloak
```

**List Resources**

```bash
# List all running tasks with details
python3 get_ecs_logs.py list-tasks

# List all services with status
python3 get_ecs_logs.py list-services
```

#### Options

| Command | Option | Description |
|---------|--------|-------------|
| All log commands | `--follow` | Follow logs in real-time |
| All log commands | `--minutes N` | Show logs from last N minutes |
| Log commands | `--filter PATTERN` | Filter logs by grep pattern |
| alb-logs | `--alb {registry,keycloak}` | Choose which ALB to query |

#### Examples

```bash
# Follow all service logs
python3 get_ecs_logs.py all-logs --follow

# Get last 2 hours of auth logs
python3 get_ecs_logs.py auth-logs --minutes 120

# Get logs containing "warning"
python3 get_ecs_logs.py registry-logs --filter "warning"

# Get ALB access logs
python3 get_ecs_logs.py alb-logs --alb registry

# List all services
python3 get_ecs_logs.py list-services
```

## Log Groups

The ECS cluster uses the following CloudWatch log groups:

| Service | Log Group |
|---------|-----------|
| Auth Server | `/ecs/mcp-gateway-ecs-auth-server` |
| Registry | `/ecs/mcp-gateway-ecs-registry` |
| Keycloak | `/ecs/mcp-gateway-ecs-keycloak` |

## ALB Logs

ALB access logs are stored in S3 with the following structure:

```
s3://[bucket-name]/[prefix]/AWSLogs/[account-id]/elasticloadbalancing/[region]/[alb-id]/[date]/...
```

### Log Format

ALB logs contain the following fields:

```
type time elb client:port target:port request_processing_time target_processing_time response_processing_time elb_status_code target_status_code received_bytes sent_bytes request target_group_arn trace_id domain_name chosen_cert_arn matched_rule_priority request_creation_time actions_executed redirect_info error_reason target_port_list ...
```

### Downloading and Parsing ALB Logs

```bash
# Get latest log file info from alb-logs output
# Then download it:
aws s3 cp s3://bucket-name/path/to/log.gz . --region us-east-1

# Extract and view
gunzip log.gz
cat log

# Or search with grep
grep "5xx" log | head -20

# Count errors by type
grep "5xx" log | cut -d' ' -f9 | sort | uniq -c

# Get slowest responses
awk '{print $8, $7, $9}' log | sort -rn | head -10
```

## Environment Variables

Set these to override defaults:

```bash
export AWS_REGION=us-east-1          # AWS region
export AWS_PROFILE=myprofile          # AWS profile to use
```

## CloudWatch Insights Queries

You can also use CloudWatch Logs Insights for more advanced queries:

```bash
aws logs start-query \
  --log-group-name "/ecs/mcp-gateway-ecs-registry" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | stats count() by @message'
```

## Common Scenarios

### Monitor Application Health

```bash
# Follow all service logs
python3 get_ecs_logs.py all-logs --follow

# Or individually
./get-ecs-logs.sh auth-logs --follow
./get-ecs-logs.sh registry-logs --follow
./get-ecs-logs.sh keycloak-logs --follow
```

### Find Errors

```bash
# Search for ERROR logs in last 60 minutes
./get-ecs-logs.sh registry-logs --minutes 60 --filter "ERROR"

# Find 5xx errors in ALB
./get-ecs-logs.sh alb-logs --alb registry --error-only
```

### Performance Analysis

```bash
# Get last 100 lines to see recent activity
./get-ecs-logs.sh registry-logs --tail 200

# Follow and grep for slow requests
python3 get_ecs_logs.py auth-logs --follow --filter "duration"
```

### Debug Startup Issues

```bash
# Get keycloak startup logs from last 10 minutes
./get-ecs-logs.sh keycloak-logs --minutes 10

# Follow startup process
python3 get_ecs_logs.py keycloak-logs --follow
```

### Check Task Status

```bash
# List running tasks
./get-ecs-logs.sh list-tasks

# Check service status
./get-ecs-logs.sh list-services
```

## Troubleshooting

### "Log group not found"

The service hasn't created a log group yet. This typically happens when:

1. The service has never started successfully
2. The service definition doesn't have CloudWatch logging enabled

**Solution**: Check the ECS service status and task definitions

```bash
./get-ecs-logs.sh list-services
./get-ecs-logs.sh list-tasks
```

### "No running tasks"

All instances of the service are stopped.

**Solution**: Check ALB target health and restart services if needed

```bash
# Get detailed task information
python3 get_ecs_logs.py list-tasks
```

### "ALB logging not enabled"

ALB access logs aren't configured.

**Solution**: Enable ALB logging in Terraform (requires S3 bucket configuration)

### AWs Credentials Issues

If you get permission errors:

1. Check AWS credentials: `aws sts get-caller-identity`
2. Ensure you have proper IAM permissions (see Prerequisites)
3. Set AWS profile: `export AWS_PROFILE=your-profile`

## Advanced Usage

### Parse ALB Logs for Analysis

```bash
# Get ALB logs details
python3 get_ecs_logs.py alb-logs --alb registry

# Download latest log
aws s3 cp s3://[bucket]/[latest-key] . --region us-east-1
gunzip *.gz

# Analyze with awk
awk '{print $9}' *.log | sort | uniq -c | sort -rn  # Status codes

awk '{print $6}' *.log | cut -d: -f2 | sort | uniq   # Target hosts

awk '$9 >= 400 {print}' *.log | head -20             # Error responses
```

### Monitor Over Time

```bash
# Create monitoring loop
while true; do
  clear
  echo "=== ECS Task Status ==="
  ./get-ecs-logs.sh list-tasks
  echo ""
  echo "=== Last 20 lines of each service ==="
  ./get-ecs-logs.sh ecs-logs --tail 20
  sleep 30
done
```

### Export Logs for Analysis

```bash
# Export last 24 hours of logs to file
./get-ecs-logs.sh registry-logs --minutes 1440 > registry-logs-24h.txt

# Export all service logs
for service in auth registry keycloak; do
  ./get-ecs-logs.sh ${service}-logs --minutes 1440 > ${service}-logs-24h.txt
done
```

## Integration Examples

### With jq for JSON Parsing

```bash
# Get task details as JSON
aws ecs list-tasks --cluster mcp-gateway-ecs-cluster \
  | jq -r '.taskArns[0]'

# Get running task count
aws ecs describe-services \
  --cluster mcp-gateway-ecs-cluster \
  --services mcp-gateway-ecs-registry \
  | jq '.services[0].runningCount'
```

### With grep for Advanced Filtering

```bash
# Get logs, extract specific patterns
./get-ecs-logs.sh registry-logs --minutes 60 | grep "HTTP.*5\|ERROR\|FATAL"

# Get unique error messages
./get-ecs-logs.sh auth-logs --minutes 120 | grep -o "error:.*" | sort | uniq -c
```

## Performance Tips

1. **Use appropriate time windows**: Don't query too far back (large log volumes)
2. **Use filters**: Filter on the client side with `--filter` option
3. **Tail instead of full logs**: Use `--tail` for recent activity
4. **Follow for real-time**: Use `--follow` instead of polling
5. **Archive old logs**: Consider exporting logs to S3 for long-term storage

## Further Reading

- [AWS CloudWatch Logs Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [AWS ECS Logging](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_cloudwatch_logs.html)
- [ALB Access Logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-access-logs.html)
