#!/bin/bash

################################################################################
# Register Demo Servers Script for MCP Gateway
#
# This script automatically registers demo MCP servers to the registry:
# - AI Registry Tools (mcpgw server)
# - Current Time API
#
# It's designed to be called from post-deployment scripts in various
# deployment environments (local, ECS, EKS).
#
# Usage:
#   ./register-demo-servers.sh [OPTIONS]
#
# Options:
#   --registry-url URL     Registry URL (default: http://localhost)
#   --token-file PATH      Path to admin M2M token JSON file
#   --token TOKEN          Admin M2M bearer token (alternative to --token-file)
#   --skip-airegistry      Skip registering AI Registry Tools server
#   --skip-currenttime     Skip registering Current Time API server
#   --dry-run              Show what would be done without executing
#   --help                 Show this help message
#
# Environment Variables (alternatives to flags):
#   REGISTRY_URL           Registry base URL
#   ADMIN_TOKEN            Admin M2M bearer token
#   ADMIN_TOKEN_FILE       Path to admin M2M token JSON file
#
# Examples:
#   # Using token file
#   ./register-demo-servers.sh --registry-url https://registry.example.com \
#       --token-file .oauth-tokens/registry-admin-m2m-bot.json
#
#   # Using bearer token directly
#   export ADMIN_TOKEN="eyJ0eXAi..."
#   ./register-demo-servers.sh --registry-url https://registry.example.com
#
################################################################################

set -euo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXAMPLES_DIR="$PROJECT_ROOT/cli/examples"

# Defaults
REGISTRY_URL="${REGISTRY_URL:-http://localhost}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
ADMIN_TOKEN_FILE="${ADMIN_TOKEN_FILE:-}"
SKIP_AIREGISTRY=false
SKIP_CURRENTTIME=false
DRY_RUN=false


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


log_step() {
    echo ""
    echo -e "${BOLD}=========================================="
    echo -e "$1"
    echo -e "==========================================${NC}"
}


show_help() {
    grep '^#' "$0" | tail -n +2 | head -42 | sed 's/^# //' | sed 's/^#//'
    exit 0
}


_parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --registry-url)
                REGISTRY_URL="$2"
                shift 2
                ;;
            --token-file)
                ADMIN_TOKEN_FILE="$2"
                shift 2
                ;;
            --token)
                ADMIN_TOKEN="$2"
                shift 2
                ;;
            --skip-airegistry)
                SKIP_AIREGISTRY=true
                shift
                ;;
            --skip-currenttime)
                SKIP_CURRENTTIME=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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
}


_check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    # Check required tools
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    # Check Python and uv for registry_management.py
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi

    if ! command -v uv &> /dev/null; then
        missing+=("uv")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Please install them before running this script."
        exit 1
    fi

    log_success "All prerequisites met."
}


_load_token() {
    log_info "Loading admin token..."

    # Priority: --token flag > --token-file flag > ADMIN_TOKEN env > ADMIN_TOKEN_FILE env
    if [[ -z "$ADMIN_TOKEN" && -n "$ADMIN_TOKEN_FILE" ]]; then
        if [[ ! -f "$ADMIN_TOKEN_FILE" ]]; then
            log_error "Token file not found: $ADMIN_TOKEN_FILE"
            exit 1
        fi

        log_info "Loading token from file: $ADMIN_TOKEN_FILE"

        # Extract access_token from JSON file
        ADMIN_TOKEN=$(jq -r '.access_token // .token // empty' "$ADMIN_TOKEN_FILE" 2>/dev/null)

        if [[ -z "$ADMIN_TOKEN" ]]; then
            log_error "Could not extract access_token from $ADMIN_TOKEN_FILE"
            log_error "Expected JSON format: {\"access_token\": \"...\"} or {\"token\": \"...\"}"
            exit 1
        fi
    fi

    if [[ -z "$ADMIN_TOKEN" ]]; then
        log_error "No admin token provided."
        log_error "Use --token, --token-file, or set ADMIN_TOKEN/ADMIN_TOKEN_FILE environment variable."
        exit 1
    fi

    log_success "Admin token loaded successfully."
}


_wait_for_registry() {
    log_info "Waiting for registry to be ready..."

    local max_attempts=30
    local wait_interval=10
    local health_url="${REGISTRY_URL}/health"

    for attempt in $(seq 1 $max_attempts); do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$health_url" 2>/dev/null || echo "000")

        if [[ "$http_code" == "200" ]]; then
            log_success "Registry is ready!"
            return 0
        fi

        log_info "Attempt $attempt/$max_attempts - Registry not ready (HTTP $http_code), waiting ${wait_interval}s..."
        sleep $wait_interval
    done

    log_error "Registry did not become ready in time."
    log_warning "Proceeding anyway, but registration may fail."
}


_register_server() {
    local config_file="$1"
    local server_name="$2"

    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    log_info "Registering: $server_name"
    log_info "  Config: $config_file"
    log_info "  Registry: $REGISTRY_URL"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would register: $server_name"
        return 0
    fi

    # Create temporary token file if we have token directly
    local token_file_arg=""
    local temp_token_file=""

    if [[ -n "$ADMIN_TOKEN_FILE" ]]; then
        # Use existing token file
        token_file_arg="--token-file $ADMIN_TOKEN_FILE"
    elif [[ -n "$ADMIN_TOKEN" ]]; then
        # Create temporary token file from bearer token
        temp_token_file=$(mktemp)
        echo "{\"access_token\": \"$ADMIN_TOKEN\"}" > "$temp_token_file"
        token_file_arg="--token-file $temp_token_file"
    fi

    # Use registry_management.py for registration
    local cmd="uv run python $PROJECT_ROOT/api/registry_management.py --registry-url $REGISTRY_URL $token_file_arg register --config $config_file --overwrite"

    # Run registration
    if eval "$cmd" 2>&1 | grep -v "^20[0-9][0-9]-"; then
        # Clean up temp file if created
        [[ -n "$temp_token_file" ]] && rm -f "$temp_token_file"
        log_success "Registered: $server_name"
        return 0
    else
        # Clean up temp file if created
        [[ -n "$temp_token_file" ]] && rm -f "$temp_token_file"
        log_error "Failed to register: $server_name"
        return 1
    fi
}


_register_airegistry() {
    log_step "Registering AI Registry Tools"

    if [[ "$SKIP_AIREGISTRY" == "true" ]]; then
        log_warning "Skipping AI Registry Tools (--skip-airegistry)"
        return 0
    fi

    local config_file="$EXAMPLES_DIR/airegistry.json"

    if _register_server "$config_file" "AI Registry Tools"; then
        log_success "AI Registry Tools server registered successfully"
    else
        log_warning "AI Registry Tools registration failed (non-fatal, continuing)"
    fi
}


_register_currenttime() {
    log_step "Registering Current Time API"

    if [[ "$SKIP_CURRENTTIME" == "true" ]]; then
        log_warning "Skipping Current Time API (--skip-currenttime)"
        return 0
    fi

    local config_file="$EXAMPLES_DIR/currenttime.json"

    if _register_server "$config_file" "Current Time API"; then
        log_success "Current Time API server registered successfully"
    else
        log_warning "Current Time API registration failed (non-fatal, continuing)"
    fi
}


_print_summary() {
    echo ""
    log_step "Registration Summary"
    echo ""
    echo "Registry URL: $REGISTRY_URL"
    echo ""
    echo "Registered servers:"
    if [[ "$SKIP_AIREGISTRY" == "false" ]]; then
        echo "  - AI Registry Tools (/airegistry-tools/)"
    fi
    if [[ "$SKIP_CURRENTTIME" == "false" ]]; then
        echo "  - Current Time API (/currenttime/)"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Verify registration: curl ${REGISTRY_URL}/api/servers/list"
    echo "  2. Test servers:"
    echo "     curl -X POST ${REGISTRY_URL}/airegistry-tools/mcp \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -H 'Accept: application/json, text/event-stream' \\"
    echo "       -d '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"params\":{},\"id\":1}'"
    echo ""
}


main() {
    _parse_arguments "$@"

    echo -e "${BOLD}=========================================="
    echo -e "MCP Gateway - Register Demo Servers"
    echo -e "==========================================${NC}"
    echo ""
    echo "Registry URL: $REGISTRY_URL"
    echo "Dry Run: $DRY_RUN"
    echo ""

    _check_prerequisites
    _load_token
    _wait_for_registry

    # Register servers
    _register_airegistry || true
    _register_currenttime || true

    _print_summary
}


# Run main function
main "$@"
