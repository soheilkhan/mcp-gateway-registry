#!/usr/bin/env bash
set -euo pipefail

command -v aws >/dev/null 2>&1 || { echo "aws CLI is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
if [[ -z "$AWS_REGION" ]]; then
  echo "Set AWS_REGION or configure it via 'aws configure'." >&2
  exit 1
fi

CLUSTER_NAME="${CLUSTER_NAME:-mcp-gateway-ecs-cluster}"
REGISTRY_SERVICE="${REGISTRY_SERVICE:-mcp-gateway-v2-registry}"
SERVICE_NAME="${SERVICE_NAME:-mcp-gateway-v2-currenttime}"
TASK_FAMILY="${TASK_FAMILY:-mcp-gateway-v2-currenttime}"
CURRENTTIME_IMAGE="${CURRENTTIME_IMAGE:-mcpgateway/currenttime-server:latest}"
DESIRED_COUNT="${CURRENTTIME_DESIRED_COUNT:-2}"
TASK_CPU="${CURRENTTIME_CPU:-512}"
TASK_MEMORY="${CURRENTTIME_MEMORY:-1024}"
CURRENTTIME_PORT="${CURRENTTIME_PORT:-8000}"
MCP_TRANSPORT="${MCP_TRANSPORT:-streamable-http}"
LOG_GROUP="${CURRENTTIME_LOG_GROUP:-/ecs/mcp-gateway-v2-currenttime}"
TASK_ROLE_NAME="${TASK_ROLE_NAME:-mcp-gateway-v2-currenttime-task}"
EXEC_ROLE_NAME="${EXEC_ROLE_NAME:-mcp-gateway-v2-currenttime-exec}"
SG_NAME="${CURRENTTIME_SG_NAME:-mcp-gateway-v2-currenttime}"
SERVICE_CONNECT_DNS="${CURRENTTIME_SERVICE_CONNECT_DNS:-currenttime-server}"
SERVICE_CONNECT_PORT_NAME="${CURRENTTIME_SERVICE_CONNECT_PORT_NAME:-currenttime}"
PLATFORM_VERSION="${PLATFORM_VERSION:-1.4.0}"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text --region "$AWS_REGION")
log "Using AWS account $ACCOUNT_ID in $AWS_REGION"

REGISTRY_DESC=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$REGISTRY_SERVICE" \
  --region "$AWS_REGION")

if [[ $(echo "$REGISTRY_DESC" | jq '.services | length') -eq 0 ]]; then
  echo "Registry service '$REGISTRY_SERVICE' not found in cluster '$CLUSTER_NAME'." >&2
  exit 1
fi

PRIMARY_DEPLOYMENT=$(echo "$REGISTRY_DESC" | jq '.services[0].deployments[] | select(.status=="PRIMARY")')
if [[ -z "$PRIMARY_DEPLOYMENT" ]]; then
  echo "Unable to find PRIMARY deployment details for $REGISTRY_SERVICE." >&2
  exit 1
fi

SUBNET_CSV=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.networkConfiguration.awsvpcConfiguration.subnets | join(",")')
if [[ -z "$SUBNET_CSV" ]]; then
  echo "Unable to read subnet list from registry deployment." >&2
  exit 1
fi
REGISTRY_SG=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.networkConfiguration.awsvpcConfiguration.securityGroups[0]')
SERVICE_CONNECT_NAMESPACE=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.serviceConnectConfiguration.namespace')
FIRST_SUBNET=$(echo "$PRIMARY_DEPLOYMENT" | jq -r '.networkConfiguration.awsvpcConfiguration.subnets[0]')
if [[ -z "$SERVICE_CONNECT_NAMESPACE" || "$SERVICE_CONNECT_NAMESPACE" == "null" ]]; then
  echo "Registry service is not using Service Connect; please enable it first." >&2
  exit 1
fi
if [[ -z "$REGISTRY_SG" || "$REGISTRY_SG" == "null" ]]; then
  echo "Unable to read registry security group from deployment metadata." >&2
  exit 1
fi

VPC_ID=$(aws ec2 describe-subnets --subnet-ids "$FIRST_SUBNET" --region "$AWS_REGION" --query 'Subnets[0].VpcId' --output text)
log "Discovered VPC $VPC_ID, subnets [$SUBNET_CSV], registry SG $REGISTRY_SG"

TRUST_DOC=$(mktemp)
trap 'rm -f "$TRUST_DOC"' EXIT
cat > "$TRUST_DOC" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

ensure_role() {
  local role_name=$1
  if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    log "IAM role $role_name already exists"
  else
    log "Creating IAM role $role_name"
    aws iam create-role --role-name "$role_name" --assume-role-policy-document file://"$TRUST_DOC" >/dev/null
  fi
}

ensure_role "$TASK_ROLE_NAME"
ensure_role "$EXEC_ROLE_NAME"
aws iam attach-role-policy --role-name "$EXEC_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null 2>&1 || true

TASK_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$TASK_ROLE_NAME"
EXEC_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$EXEC_ROLE_NAME"
log "Task role: $TASK_ROLE_ARN"

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$AWS_REGION" --query 'logGroups[?logGroupName==`'"$LOG_GROUP"'`]' --output text | grep -q "$LOG_GROUP"; then
  log "Log group $LOG_GROUP already exists"
else
  log "Creating log group $LOG_GROUP"
  aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION"
fi

CURRENTTIME_SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$SG_NAME" \
  --region "$AWS_REGION" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)

if [[ -z "$CURRENTTIME_SG_ID" || "$CURRENTTIME_SG_ID" == "None" ]]; then
  log "Creating security group $SG_NAME"
  CURRENTTIME_SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "CurrentTime MCP server" \
    --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value='"$SG_NAME"'},{Key=stack,Value=mcp-gateway-v2},{Key=component,Value=currenttime}]' \
    --region "$AWS_REGION" \
    --query 'GroupId' --output text)
else
  log "Reusing security group $CURRENTTIME_SG_ID ($SG_NAME)"
fi

aws ec2 authorize-security-group-ingress \
  --group-id "$CURRENTTIME_SG_ID" \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":'"$CURRENTTIME_PORT"',"ToPort":'"$CURRENTTIME_PORT"',"UserIdGroupPairs":[{"GroupId":"'"$REGISTRY_SG"'","Description":"Allow registry tasks"}]}]' \
  --region "$AWS_REGION" >/dev/null 2>&1 || true

TASKDEF_FILE=$(mktemp)
trap 'rm -f "$TRUST_DOC" "$TASKDEF_FILE"' EXIT
cat > "$TASKDEF_FILE" <<JSON
{
  "family": "$TASK_FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "$TASK_CPU",
  "memory": "$TASK_MEMORY",
  "executionRoleArn": "$EXEC_ROLE_ARN",
  "taskRoleArn": "$TASK_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "currenttime-server",
      "image": "$CURRENTTIME_IMAGE",
      "essential": true,
      "portMappings": [
        {
          "containerPort": $CURRENTTIME_PORT,
          "protocol": "tcp",
          "name": "$SERVICE_CONNECT_PORT_NAME"
        }
      ],
      "environment": [
        {"name": "PORT", "value": "$CURRENTTIME_PORT"},
        {"name": "MCP_TRANSPORT", "value": "$MCP_TRANSPORT"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$LOG_GROUP",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
JSON

log "Registering task definition $TASK_FAMILY"
TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json file://"$TASKDEF_FILE" --region "$AWS_REGION" --query 'taskDefinition.taskDefinitionArn' --output text)
log "New task definition: $TASK_DEF_ARN"

NETWORK_CFG="awsvpcConfiguration={subnets=[$SUBNET_CSV],securityGroups=[$CURRENTTIME_SG_ID],assignPublicIp=DISABLED}"
SC_CFG="enabled=true,namespace=$SERVICE_CONNECT_NAMESPACE,services=[{portName=\"$SERVICE_CONNECT_PORT_NAME\",discoveryName=\"$SERVICE_CONNECT_DNS\",clientAliases=[{port=$CURRENTTIME_PORT,dnsName=\"$SERVICE_CONNECT_DNS\"}]}]"

SERVICE_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$AWS_REGION" --query 'services[0].status' --output text 2>/dev/null || echo "MISSING")

if [[ "$SERVICE_STATUS" == "ACTIVE" || "$SERVICE_STATUS" == "DRAINING" ]]; then
  log "Updating existing ECS service $SERVICE_NAME"
  aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --desired-count "$DESIRED_COUNT" \
    --enable-execute-command \
    --force-new-deployment \
    --service-connect-configuration "$SC_CFG" \
    --region "$AWS_REGION" >/dev/null
else
  log "Creating ECS service $SERVICE_NAME"
  aws ecs create-service \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --desired-count "$DESIRED_COUNT" \
    --launch-type FARGATE \
    --platform-version "$PLATFORM_VERSION" \
    --enable-execute-command \
    --network-configuration "$NETWORK_CFG" \
    --service-connect-configuration "$SC_CFG" \
    --region "$AWS_REGION" >/dev/null
fi

log "Deployment kicked off. Check service status with:\n  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION --query 'services[0].deployments'
"
