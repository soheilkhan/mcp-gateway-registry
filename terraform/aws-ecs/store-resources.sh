#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCES_FILE="${SCRIPT_DIR}/.resources"

_log_info() {
    echo "[INFO] $1"
}

_log_error() {
    echo "[ERROR] $1" >&2
}

_log_success() {
    echo "[SUCCESS] $1"
}

# Run terraform output and store results
_log_info "Fetching Terraform outputs..."

if ! terraform -chdir="${SCRIPT_DIR}" output -json > /tmp/tf_output.json 2>/dev/null; then
    _log_error "Failed to get Terraform outputs. Make sure you're in the correct directory."
    exit 1
fi

# Parse Terraform output and extract useful information
_log_info "Parsing Terraform outputs..."

{
    echo "# ECS Resources Configuration"
    echo "# Generated: $(date)"
    echo ""

    # ECS Cluster
    CLUSTER_NAME=$(jq -r '.ecs_cluster_name.value // "mcp-gateway-ecs-cluster"' /tmp/tf_output.json)
    echo "ECS_CLUSTER_NAME=${CLUSTER_NAME}"

    CLUSTER_ARN=$(jq -r '.ecs_cluster_arn.value // ""' /tmp/tf_output.json)
    echo "ECS_CLUSTER_ARN=${CLUSTER_ARN}"

    # AWS Region
    AWS_REGION=$(jq -r '.deployment_summary.value.region // "us-east-1"' /tmp/tf_output.json)
    if [ "$AWS_REGION" = "null" ] || [ -z "$AWS_REGION" ]; then
        AWS_REGION="us-east-1"
    fi
    echo "AWS_REGION=${AWS_REGION}"

    echo ""
    echo "# ECS Services Log Groups"
    # Extract name prefix from cluster name (remove -ecs-cluster suffix)
    NAME_PREFIX=$(echo "${CLUSTER_NAME}" | sed 's/-ecs-cluster$//')
    echo "LOG_GROUP_AUTH=/ecs/${NAME_PREFIX}-auth-server"
    echo "LOG_GROUP_REGISTRY=/ecs/${NAME_PREFIX}-registry"
    echo "LOG_GROUP_KEYCLOAK=/ecs/${NAME_PREFIX}-keycloak"

    echo ""
    echo "# ALB Information"
    ALB_REGISTRY=$(jq -r '.mcp_gateway_alb_dns.value // ""' /tmp/tf_output.json)
    ALB_KEYCLOAK=$(jq -r '.keycloak_alb_dns.value // ""' /tmp/tf_output.json)
    echo "ALB_REGISTRY_DNS=${ALB_REGISTRY}"
    echo "ALB_KEYCLOAK_DNS=${ALB_KEYCLOAK}"

    echo ""
    echo "# URLs"
    REGISTRY_URL=$(jq -r '.mcp_gateway_url.value // ""' /tmp/tf_output.json)
    AUTH_URL=$(jq -r '.mcp_gateway_auth_url.value // ""' /tmp/tf_output.json)
    KEYCLOAK_URL=$(jq -r '.mcp_gateway_keycloak_url.value // ""' /tmp/tf_output.json)
    echo "REGISTRY_URL=${REGISTRY_URL}"
    echo "AUTH_URL=${AUTH_URL}"
    echo "KEYCLOAK_URL=${KEYCLOAK_URL}"

    echo ""
    echo "# VPC and Networking"
    VPC_ID=$(jq -r '.vpc_id.value // ""' /tmp/tf_output.json)
    echo "VPC_ID=${VPC_ID}"

    echo ""
    echo "# Deployment Status"
    MONITORING_ENABLED=$(jq -r '.deployment_summary.value.monitoring_enabled // "false"' /tmp/tf_output.json)
    HTTPS_ENABLED=$(jq -r '.deployment_summary.value.https_enabled // "false"' /tmp/tf_output.json)
    echo "MONITORING_ENABLED=${MONITORING_ENABLED}"
    echo "HTTPS_ENABLED=${HTTPS_ENABLED}"

} > "${RESOURCES_FILE}"

# Verify file was created
if [ ! -f "${RESOURCES_FILE}" ]; then
    _log_error "Failed to create resources file"
    exit 1
fi

# Display the contents
_log_success "Resources stored in ${RESOURCES_FILE}"
echo ""
echo "Contents:"
cat "${RESOURCES_FILE}"

# Cleanup
rm -f /tmp/tf_output.json

_log_success "Resource discovery complete"
