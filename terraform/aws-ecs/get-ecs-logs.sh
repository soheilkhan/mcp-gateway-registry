#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCES_FILE="${SCRIPT_DIR}/.resources"

# Load resources from file if it exists
if [ -f "${RESOURCES_FILE}" ]; then
    source "${RESOURCES_FILE}"
fi

# Configuration (use loaded values or defaults)
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${ECS_CLUSTER_NAME:-mcp-gateway-ecs-cluster}"
FOLLOW="${FOLLOW:-false}"
MINUTES="${MINUTES:-30}"
TAIL_LINES="${TAIL_LINES:-100}"
SERVICE_FILTER="${SERVICE_FILTER:-}"

# Color codes for output (disabled if not in terminal)
if [ -t 1 ]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    NC=$'\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Functions for colored output
_log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

_log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

_log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

_log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

_show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    ecs-logs           Get ECS task logs (default)
    alb-logs           Get ALB access logs
    keycloak-logs      Get Keycloak task logs
    auth-logs          Get Auth service logs
    registry-logs      Get Registry service logs
    all-logs           Get logs from all services
    list-tasks         List all running ECS tasks
    list-services      List all ECS services
    help               Show this help message

Options for ecs-logs and service-specific logs:
    --follow           Follow logs in real-time (like 'tail -f')
    --minutes N        Show logs from last N minutes (default: ${MINUTES})
    --tail N           Show last N lines (default: ${TAIL_LINES})
    --region REGION    AWS region (default: ${AWS_REGION})
    --cluster NAME     ECS cluster name (default: ${CLUSTER_NAME})
    --filter TEXT      Filter logs by text/pattern (grep)
    --raw              Show raw JSON instead of formatted logs

Options for alb-logs:
    --alb NAME         ALB name (registry or keycloak)
    --minutes N        Show logs from last N minutes (default: ${MINUTES})
    --filter TEXT      Filter logs by text/pattern
    --error-only       Show only 4xx and 5xx errors

Examples:
    # Get last 100 lines of registry logs
    $0 registry-logs

    # Follow auth service logs in real-time
    $0 auth-logs --follow

    # Get last 30 minutes of logs
    $0 ecs-logs --minutes 30

    # Get all logs from all services
    $0 all-logs --follow

    # Get ALB logs with errors only
    $0 alb-logs --alb registry --error-only

    # Get logs filtered by text
    $0 registry-logs --filter "error"

EOF
}

_get_cluster_arn() {
    aws ecs describe-clusters \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'clusters[0].clusterArn' \
        --output text
}

_list_services() {
    aws ecs list-services \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'serviceArns[]' \
        --output text | tr '\t' '\n'
}

_list_running_tasks() {
    local service="$1"

    if [ -z "$service" ]; then
        # List all tasks across all services
        aws ecs list-tasks \
            --cluster "$CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --query 'taskArns[]' \
            --output text | tr '\t' '\n'
    else
        # List tasks for specific service
        aws ecs list-tasks \
            --cluster "$CLUSTER_NAME" \
            --service-name "$service" \
            --region "$AWS_REGION" \
            --query 'taskArns[]' \
            --output text | tr '\t' '\n'
    fi
}

_get_task_details() {
    local task_arn="$1"

    aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$task_arn" \
        --region "$AWS_REGION" \
        --output json
}

_get_log_group_name() {
    local service="$1"

    # Try to use values from resources file first
    case "$service" in
        auth-server)
            echo "${LOG_GROUP_AUTH:-/ecs/${CLUSTER_NAME}-auth-server}"
            ;;
        registry)
            echo "${LOG_GROUP_REGISTRY:-/ecs/${CLUSTER_NAME}-registry}"
            ;;
        keycloak)
            echo "${LOG_GROUP_KEYCLOAK:-/ecs/${CLUSTER_NAME}-keycloak}"
            ;;
        *)
            echo "/ecs/${CLUSTER_NAME}-${service}"
            ;;
    esac
}

_get_ecs_logs() {
    local service="$1"
    local log_group=$(_get_log_group_name "$service")

    _log_info "Fetching logs for service: ${BLUE}${service}${NC}"
    _log_info "Log group: ${BLUE}${log_group}${NC}"

    # Check if log group exists
    if ! aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$AWS_REGION" \
        --query "logGroups[?logGroupName=='$log_group']" \
        --output text | grep -q "$log_group"; then
        _log_warning "Log group not found: $log_group"
        return 1
    fi

    # Build the logs query
    local start_time=""
    if [ "$FOLLOW" = "false" ]; then
        # Calculate start time (minutes ago)
        if command -v date &> /dev/null; then
            start_time=$(date -u -d "$MINUTES minutes ago" +%s)000
        else
            start_time=$(($(date +%s) - MINUTES * 60))000
        fi
    fi

    # Fetch logs using filter-log-events
    local start_time_ms=$(($(date +%s) - MINUTES * 60))000

    aws logs filter-log-events \
        --log-group-name "$log_group" \
        --start-time "$start_time_ms" \
        --region "$AWS_REGION" \
        --query 'events[*].[timestamp,message]' \
        --output text | tail -n "$TAIL_LINES" | while read -r timestamp message; do
            if [ -n "$timestamp" ] && [ -n "$message" ]; then
                formatted_time=$(date -d @$((timestamp / 1000)) +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
                echo "[$formatted_time] $message"
            fi
        done
}

_get_ecs_logs_filtered() {
    local service="$1"
    local filter_pattern="$2"
    local log_group=$(_get_log_group_name "$service")

    _log_info "Fetching logs for service: ${BLUE}${service}${NC}"
    _log_info "Filter pattern: ${BLUE}${filter_pattern}${NC}"

    local start_time=""
    if command -v date &> /dev/null; then
        start_time=$(($(date +%s) - MINUTES * 60))
    else
        start_time=$(($(date +%s) - MINUTES * 60))
    fi

    aws logs filter-log-events \
        --log-group-name "$log_group" \
        --start-time "$((start_time * 1000))" \
        --filter-pattern "$filter_pattern" \
        --region "$AWS_REGION" \
        --query 'events[*].[timestamp,message]' \
        --output text | while read -r timestamp message; do
            echo "[$(date -u -d @$((timestamp / 1000)) +"%Y-%m-%d %H:%M:%S")] $message"
        done
}

_list_alb_logs_in_s3() {
    # Find ALB log buckets
    local bucket=$(aws s3api list-buckets \
        --region "$AWS_REGION" \
        --query "Buckets[?contains(Name, 'alb-logs') || contains(Name, 'logs')].Name" \
        --output text | head -1)

    if [ -z "$bucket" ]; then
        _log_warning "No ALB logs bucket found"
        return 1
    fi

    _log_info "Found ALB logs bucket: ${BLUE}${bucket}${NC}"

    # List recent logs
    aws s3api list-objects-v2 \
        --bucket "$bucket" \
        --region "$AWS_REGION" \
        --query 'Contents[*].[Key,LastModified,Size]' \
        --output table
}

_get_alb_logs() {
    local alb_name="${1:-registry}"

    _log_info "Fetching ALB access logs for: ${BLUE}${alb_name}${NC}"

    # Map ALB names to actual ALB names
    local actual_alb_name
    case "$alb_name" in
        registry)
            actual_alb_name="mcp-gateway-alb"
            ;;
        keycloak)
            actual_alb_name="mcp-gateway-kc-alb"
            ;;
        *)
            actual_alb_name="$alb_name"
            ;;
    esac

    # Get ALB ARN
    local alb_arn=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?LoadBalancerName=='$actual_alb_name'].LoadBalancerArn" \
        --output text)

    if [ -z "$alb_arn" ]; then
        _log_error "ALB not found: $alb_name"
        return 1
    fi

    _log_info "ALB ARN: ${BLUE}${alb_arn}${NC}"

    # Get ALB attributes to find logs bucket
    local logs_bucket=$(aws elbv2 describe-load-balancer-attributes \
        --load-balancer-arn "$alb_arn" \
        --region "$AWS_REGION" \
        --query "Attributes[?Key=='access_logs.s3.bucket'].Value" \
        --output text)

    if [ -z "$logs_bucket" ]; then
        _log_warning "ALB logging not enabled for: $alb_name"
        _list_alb_logs_in_s3
        return 1
    fi

    _log_info "ALB logs bucket: ${BLUE}${logs_bucket}${NC}"

    # Query logs from CloudWatch Logs Insights or S3
    _log_info "Listing ALB logs from S3..."

    local prefix=$(aws elbv2 describe-load-balancer-attributes \
        --load-balancer-arn "$alb_arn" \
        --region "$AWS_REGION" \
        --query "Attributes[?Key=='access_logs.s3.prefix'].Value" \
        --output text)

    if [ "$prefix" = "None" ] || [ -z "$prefix" ]; then
        prefix=""
    fi

    aws s3api list-objects-v2 \
        --bucket "$logs_bucket" \
        --prefix "$prefix" \
        --region "$AWS_REGION" \
        --max-items 20 \
        --query 'Contents[*].[Key,LastModified,Size]' \
        --output table

    # Try to get latest log and parse it
    local latest_log=$(aws s3api list-objects-v2 \
        --bucket "$logs_bucket" \
        --prefix "$prefix" \
        --region "$AWS_REGION" \
        --query 'Contents[-1].Key' \
        --output text)

    if [ "$latest_log" != "None" ] && [ -n "$latest_log" ]; then
        _log_info "Latest ALB log file: ${BLUE}${latest_log}${NC}"
        _log_info "To download and view this log:"
        echo "    aws s3 cp s3://${logs_bucket}/${latest_log} . --region ${AWS_REGION}"
        echo "    gunzip ${latest_log##*/}"
        echo "    cat *.log"
    fi
}

_list_running_services() {
    _log_info "Listing ECS services in cluster: ${BLUE}${CLUSTER_NAME}${NC}"

    local services=$(_list_services)

    if [ -z "$services" ]; then
        _log_warning "No services found"
        return 1
    fi

    echo "$services" | while read -r service_arn; do
        local service_name=$(echo "$service_arn" | awk -F'/' '{print $NF}')
        local task_count=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$service_arn" \
            --region "$AWS_REGION" \
            --query 'services[0].runningCount' \
            --output text)

        echo -e "Service: ${GREEN}${service_name}${NC} (Running tasks: ${BLUE}${task_count}${NC})"
    done
}

_list_running_tasks_detailed() {
    _log_info "Listing running tasks in cluster: ${BLUE}${CLUSTER_NAME}${NC}"

    local tasks=$(_list_running_tasks)

    if [ -z "$tasks" ]; then
        _log_warning "No running tasks found"
        return 1
    fi

    echo "$tasks" | while read -r task_arn; do
        if [ -n "$task_arn" ]; then
            local task_details=$(_get_task_details "$task_arn")
            local task_name=$(echo "$task_details" | jq -r '.tasks[0].taskDefinitionArn' | awk -F'/' '{print $NF}')
            local task_id=$(echo "$task_arn" | awk -F'/' '{print $NF}')
            local status=$(echo "$task_details" | jq -r '.tasks[0].lastStatus')

            echo -e "Task: ${GREEN}${task_name}${NC} (ID: ${BLUE}${task_id}${NC}, Status: ${YELLOW}${status}${NC})"
        fi
    done
}

# Main command handling
COMMAND="${1:-ecs-logs}"
shift || true

case "$COMMAND" in
    ecs-logs)
        # Default: Get logs from all services
        for service in auth registry keycloak; do
            _get_ecs_logs "$service" || true
            echo ""
        done
        ;;

    auth-logs)
        _get_ecs_logs "auth-server"
        ;;

    registry-logs)
        _get_ecs_logs "registry"
        ;;

    keycloak-logs)
        _get_ecs_logs "keycloak"
        ;;

    all-logs)
        # Get logs from all services
        for service in auth-server registry keycloak; do
            _log_info "========================================"
            _log_info "Logs for service: $service"
            _log_info "========================================"
            _get_ecs_logs "$service" || true
            echo ""
        done
        ;;

    alb-logs)
        alb_name="registry"

        while [[ $# -gt 0 ]]; do
            case $1 in
                --alb)
                    alb_name="$2"
                    shift 2
                    ;;
                --error-only)
                    # TODO: Implement error filtering
                    shift
                    ;;
                *)
                    shift
                    ;;
            esac
        done

        _get_alb_logs "$alb_name"
        ;;

    list-tasks)
        _list_running_tasks_detailed
        ;;

    list-services)
        _list_running_services
        ;;

    help|-h|--help)
        _show_usage
        exit 0
        ;;

    *)
        _log_error "Unknown command: $COMMAND"
        echo ""
        _show_usage
        exit 1
        ;;
esac

# Parse additional options
while [[ $# -gt 0 ]]; do
    case $1 in
        --follow)
            FOLLOW=true
            shift
            ;;
        --minutes)
            MINUTES="$2"
            shift 2
            ;;
        --tail)
            TAIL_LINES="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

exit 0
