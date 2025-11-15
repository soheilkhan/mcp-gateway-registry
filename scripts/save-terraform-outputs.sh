#!/bin/bash

################################################################################
# Save Terraform Outputs to File
#
# This script:
# 1. Runs terraform output to get all deployed resource information
# 2. Formats the output nicely
# 3. Saves to a timestamped text file
# 4. Creates a backup of previous outputs
#
# Usage:
#   ./scripts/save-terraform-outputs.sh [OPTIONS]
#
# Options:
#   --output-file FILE         Output file path (default: terraform-outputs.txt)
#   --terraform-dir DIR        Terraform directory (default: terraform/aws-ecs)
#   --json                     Save output in JSON format instead of text
#   --no-backup                Don't create backup of previous output
#   --help                     Show this help message
#
# Examples:
#   # Save outputs with default filename
#   ./scripts/save-terraform-outputs.sh
#
#   # Save to custom file
#   ./scripts/save-terraform-outputs.sh --output-file my-resources.txt
#
#   # Save as JSON
#   ./scripts/save-terraform-outputs.sh --json
#
################################################################################

set -euo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
OUTPUT_FILE="terraform-outputs.txt"
TERRAFORM_DIR="terraform/aws-ecs"
JSON_FORMAT=false
CREATE_BACKUP=true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

show_help() {
    grep '^#' "$0" | tail -n +2 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --terraform-dir)
            TERRAFORM_DIR="$2"
            shift 2
            ;;
        --json)
            JSON_FORMAT=true
            shift
            ;;
        --no-backup)
            CREATE_BACKUP=false
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate terraform directory
TERRAFORM_PATH="$REPO_ROOT/$TERRAFORM_DIR"
if [[ ! -d "$TERRAFORM_PATH" ]]; then
    log_error "Terraform directory not found: $TERRAFORM_PATH"
    exit 1
fi

# Get absolute output path
if [[ "$OUTPUT_FILE" != /* ]]; then
    OUTPUT_FILE="$REPO_ROOT/$OUTPUT_FILE"
fi

log_info "=========================================="
log_info "Terraform Outputs Export Script"
log_info "=========================================="
log_info "Terraform Directory: $TERRAFORM_PATH"
log_info "Output Format: $([ "$JSON_FORMAT" = true ] && echo "JSON" || echo "Text")"
log_info "Output File: $OUTPUT_FILE"
log_info "Create Backup: $CREATE_BACKUP"
log_info "=========================================="

# Create backup if file exists
if [[ -f "$OUTPUT_FILE" && "$CREATE_BACKUP" == "true" ]]; then
    BACKUP_FILE="${OUTPUT_FILE}.backup-${TIMESTAMP}"
    log_info "Creating backup of previous outputs..."
    cp "$OUTPUT_FILE" "$BACKUP_FILE"
    log_success "Backup created: $BACKUP_FILE"
fi

# Run terraform output
log_info "Running terraform output..."
cd "$TERRAFORM_PATH"

if [[ "$JSON_FORMAT" == "true" ]]; then
    # JSON format
    log_info "Exporting as JSON..."
    if terraform output -json > "$OUTPUT_FILE" 2>/dev/null; then
        log_success "JSON outputs exported successfully"
    else
        log_error "Failed to export JSON outputs"
        exit 1
    fi
else
    # Text format with nice formatting
    log_info "Exporting as formatted text..."
    {
        echo "========================================"
        echo "Terraform Outputs - Generated: $(date)"
        echo "========================================"
        echo ""
        echo "Repository: $REPO_ROOT"
        echo "Terraform Dir: $TERRAFORM_DIR"
        echo "Timestamp: $TIMESTAMP"
        echo ""
        echo "========================================  OUTPUT  =========================================="
        echo ""

        terraform output

        echo ""
        echo "========================================"
        echo "Additional Resource Information"
        echo "========================================"
        echo ""

        # Add resource counts
        echo "Resource Counts:"
        terraform state list 2>/dev/null | wc -l | sed 's/^/  Total resources in state: /'
        echo ""

        # Add key resource information
        echo "Key Resources:"
        echo "  VPC ID: $(terraform output -raw vpc_id 2>/dev/null || echo 'N/A')"
        echo "  ECS Cluster: $(terraform output -raw ecs_cluster_name 2>/dev/null || echo 'N/A')"
        echo ""

        echo "========================================"
        echo "Service URLs"
        echo "========================================"
        echo "  Keycloak Admin: $(terraform output -raw keycloak_admin_console 2>/dev/null || echo 'N/A')"
        echo "  Keycloak Service: $(terraform output -raw keycloak_url 2>/dev/null || echo 'N/A')"
        echo "  Registry: $(terraform output -raw registry_url 2>/dev/null || echo 'N/A')"
        echo "  MCP Gateway: $(terraform output -raw mcp_gateway_url 2>/dev/null || echo 'N/A')"
        echo "  Auth Server: $(terraform output -raw mcp_gateway_auth_url 2>/dev/null || echo 'N/A')"
        echo ""

        echo "========================================"
        echo "Export Details"
        echo "========================================"
        echo "  Generated: $(date)"
        echo "  By: $(whoami)@$(hostname)"
        echo "  From: $(pwd)"

    } > "$OUTPUT_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Text outputs exported successfully"
    else
        log_error "Failed to export text outputs"
        exit 1
    fi
fi

# Verify file was created
if [[ -f "$OUTPUT_FILE" ]]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE")
    log_success "Output file created successfully"
    log_info "File: $OUTPUT_FILE"
    log_info "Size: $FILE_SIZE"
    log_info "Lines: $LINE_COUNT"
    echo ""

    # Show preview
    log_info "Preview of output:"
    echo "---"
    if [[ "$JSON_FORMAT" == "true" ]]; then
        head -20 "$OUTPUT_FILE"
        echo "..."
    else
        head -30 "$OUTPUT_FILE"
        echo "..."
    fi
    echo "---"

    log_success "=========================================="
    log_success "Terraform outputs saved to:"
    log_success "$OUTPUT_FILE"
    log_success "=========================================="
else
    log_error "Failed to create output file"
    exit 1
fi

exit 0
