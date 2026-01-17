#!/bin/bash
#
# Ingress Token Generator Script
#
# This script generates ingress authentication tokens using the configured
# identity provider (Keycloak or Entra ID based on AUTH_PROVIDER).
#
# Usage:
#   ./generate_creds.sh              # Generate ingress token
#   ./generate_creds.sh --verbose    # Enable verbose logging
#   ./generate_creds.sh --force      # Force new token generation
#   ./generate_creds.sh --help       # Show this help

set -e  # Exit on error

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Also load main project .env file to get AUTH_PROVIDER
if [ -f "$(dirname "$SCRIPT_DIR")/.env" ]; then
    source "$(dirname "$SCRIPT_DIR")/.env"
fi

# Export Keycloak environment variables for child processes
export KEYCLOAK_ADMIN_URL
export KEYCLOAK_EXTERNAL_URL
export KEYCLOAK_URL
export KEYCLOAK_REALM
export KEYCLOAK_M2M_CLIENT_ID
export KEYCLOAK_M2M_CLIENT_SECRET

# Export Entra ID environment variables for child processes
export ENTRA_TENANT_ID
export ENTRA_CLIENT_ID
export ENTRA_CLIENT_SECRET
export ENTRA_LOGIN_BASE_URL

# Default values
VERBOSE=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

show_help() {
    cat << EOF
Ingress Token Generator Script

This script generates ingress authentication tokens for the MCP Gateway.
It automatically uses the configured AUTH_PROVIDER (keycloak or entra).

USAGE:
    ./generate_creds.sh [OPTIONS]

OPTIONS:
    --force, -f             Force new token generation, ignore existing tokens
    --verbose, -v           Enable verbose debug logging
    --help, -h              Show this help message

EXAMPLES:
    ./generate_creds.sh                    # Generate ingress token
    ./generate_creds.sh --force            # Force new token generation
    ./generate_creds.sh --verbose          # Enable debug output
    ./generate_creds.sh --force --verbose  # Force with debug output

BEHAVIOR:
    - Reads AUTH_PROVIDER from .env file (default: keycloak)
    - AUTH_PROVIDER=keycloak: Uses Keycloak M2M client credentials flow
    - AUTH_PROVIDER=entra: Uses Microsoft Entra ID client credentials flow
    - Saves token to .oauth-tokens/ingress.json

ENVIRONMENT VARIABLES:
    General:
        AUTH_PROVIDER                  # IdP selection: 'keycloak' (default) or 'entra'

    For Keycloak (AUTH_PROVIDER=keycloak):
        KEYCLOAK_URL                   # Keycloak server URL
        KEYCLOAK_REALM                 # Keycloak realm name
        KEYCLOAK_M2M_CLIENT_ID         # M2M client ID
        KEYCLOAK_M2M_CLIENT_SECRET     # M2M client secret

    For Entra ID (AUTH_PROVIDER=entra):
        ENTRA_TENANT_ID                # Azure AD tenant ID
        ENTRA_CLIENT_ID                # App registration client ID
        ENTRA_CLIENT_SECRET            # App registration client secret
        ENTRA_LOGIN_BASE_URL           # Optional (default: https://login.microsoftonline.com)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to run Keycloak token generation
run_keycloak_auth() {
    log_info "Running Keycloak M2M token generation..."

    local cmd="uv run '$SCRIPT_DIR/keycloak/generate_tokens.py' --all-agents"

    if [ "$VERBOSE" = true ]; then
        cmd="$cmd --verbose"
    fi

    log_debug "Executing: $cmd"

    if eval "$cmd"; then
        log_info "Keycloak token generation completed successfully"
        return 0
    else
        log_error "Keycloak token generation failed"
        return 1
    fi
}

# Function to run Entra ID token generation
run_entra_auth() {
    log_info "Running Entra ID token generation..."

    local cmd="uv run '$SCRIPT_DIR/entra/generate_tokens.py' --all-agents"

    if [ "$VERBOSE" = true ]; then
        cmd="$cmd --verbose"
    fi

    log_debug "Executing: $cmd"

    if eval "$cmd"; then
        log_info "Entra ID token generation completed successfully"
        return 0
    else
        log_error "Entra ID token generation failed"
        return 1
    fi
}

# Main execution
main() {
    local auth_provider="${AUTH_PROVIDER:-keycloak}"

    log_info "Starting Ingress Token Generator"
    log_info "AUTH_PROVIDER: $auth_provider"

    local success=false

    if [ "$auth_provider" = "entra" ]; then
        if run_entra_auth; then
            success=true
        fi
    else
        if run_keycloak_auth; then
            success=true
        fi
    fi

    # Summary
    echo ""
    log_info "Summary:"
    if [ "$success" = true ]; then
        log_info "  Token generation: SUCCESS"
    else
        log_info "  Token generation: FAILED"
    fi

    log_info "Check ./.oauth-tokens/ for generated token files"

    if [ "$success" = false ]; then
        exit 1
    fi
}

# Run main function
main "$@"
