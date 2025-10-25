#!/bin/bash

# ============================================================
#  Project:   test-secured-swarm.sh
#  Author:    Fabrice TRAN-XUAN
#  Created:   2025-08-10
#
#  License:   MIT License
#
#  Permission is hereby granted, free of charge, to any person
#  obtaining a copy of this software and associated documentation
#  files (the "Software"), to deal in the Software without
#  restriction, including without limitation the rights to use,
#  copy, modify, merge, publish, distribute, sublicense, and/or
#  sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following
#  conditions:
#
#  The above copyright notice and this permission notice shall be
#  included in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#  OTHER DEALINGS IN THE SOFTWARE.
# ============================================================

source "../commons/commons-log.sh"

# Counters
SECURED_COUNT=0
UNSECURED_COUNT=0
TOTAL_SERVICES=0

#
# Function: usage
# Display usage
#
usage() {
    log_debug "Usage: $0 --docker-compose <path-to-docker-compose.yml>"
    exit 1
}

#
# Function: check_service_security
# Check if a service is secured
# Parameters:
#   $1 - Service name
#
#
# Function: check_service_security
# Check if a service is secured
# Parameters:
#   $1 - Service name
#
check_service_security() {
    local SERVICE_NAME_ARG="$1"

    log_info "Checking service: ${SERVICE_NAME_ARG}"

    # Find container ID: try name filter, then compose label fallback
    local CID
    CID=$(sudo docker ps --filter "name=${SERVICE_NAME_ARG}" --format '{{.ID}}' | head -n1)
    if [ -z "$CID" ]; then
        CID=$(sudo docker ps --filter "label=com.docker.compose.service=${SERVICE_NAME_ARG}" --format '{{.ID}}' | head -n1)
    fi

    if [ -z "$CID" ]; then
        log_warning "⚠ No running container found for service: ${SERVICE_NAME_ARG}${NC}"
        return
    fi

    log_debug "  Container ID: ${CID}"

    # Ensure container is running
    local STATE
    STATE=$(sudo docker inspect --format '{{.State.Status}}' "$CID" 2>/dev/null || echo "unknown")
    if [ "$STATE" != "running" ]; then
        log_warning "⚠ Container $CID is not running (state: ${STATE}) - skipping deeper checks${NC}"
        ((UNSECURED_COUNT++))
        log_error "  ✗ UNSECURED: Container not running or accessible${NC}"
        return
    fi

    # Inspect runtime configuration
    local INSPECT
    INSPECT=$(sudo docker inspect "$CID" 2>/dev/null)
    if [ -z "$INSPECT" ]; then
        log_error "  ✗ UNSECURED: Failed to inspect container $CID${NC}"
        ((UNSECURED_COUNT++))
        return
    fi

    # Extract attributes
    local RUN_AS_USER
    RUN_AS_USER=$(sudo docker inspect --format '{{.Config.User}}' "$CID" 2>/dev/null || echo "")
    local PRIVILEGED
    PRIVILEGED=$(sudo docker inspect --format '{{.HostConfig.Privileged}}' "$CID" 2>/dev/null || echo "false")
    local CAPADD
    CAPADD=$(sudo docker inspect --format '{{json .HostConfig.CapAdd}}' "$CID" 2>/dev/null || echo "null")
    local TTY
    TTY=$(sudo docker inspect --format '{{.Config.Tty}}' "$CID" 2>/dev/null || echo "false")
    local OPEN_STDIN
    OPEN_STDIN=$(sudo docker inspect --format '{{.Config.OpenStdin}}' "$CID" 2>/dev/null || echo "false")

    # Collect security issues
    local -a ISSUES=()

    # Check user (empty means root)
    if [ -z "$RUN_AS_USER" ]; then
        ISSUES+=("runs as root")
    else
        # consider numeric uid or root name
        case "$RUN_AS_USER" in
            0|root|root:*)
                ISSUES+=("runs as root")
                ;;
        esac
    fi

    # Privileged
    if [ "$PRIVILEGED" = "true" ]; then
        ISSUES+=("privileged mode enabled")
    fi

    # Capabilities added
    if [ "$CAPADD" != "null" ] && [ "$CAPADD" != "[]" ]; then
        # remove whitespace/newlines for readable check
        local CAPADD_CLEAN
        CAPADD_CLEAN=$(echo "$CAPADD" | tr -d '\n' | tr -d ' ')
        ISSUES+=("capabilities added: ${CAPADD_CLEAN}")
    fi

    # TTY / OpenStdin (interactive)
    if [ "$TTY" = "true" ] || [ "$OPEN_STDIN" = "true" ]; then
        ISSUES+=("interactive tty or open stdin enabled")
    fi

    # Check for shell availability inside container (non-interactive)
    if sudo docker exec "$CID" sh -c 'command -v sh >/dev/null 2>&1 && echo yes || echo no' >/tmp/.svc_check_sh_out 2>/dev/null; then
        if grep -q '^yes$' /tmp/.svc_check_sh_out 2>/dev/null; then
            ISSUES+=("shell available inside container")
        fi
    fi
    rm -f /tmp/.svc_check_sh_out 2>/dev/null || true

    # Optionally check docker-compose config for insecure keys (if CONFIGURATION_FILE present)
    if [ -n "$CONFIGURATION_FILE" ] && [ -f "$CONFIGURATION_FILE" ]; then
        # Check if service has tty: true or privileged: true in compose file
        local COMPOSE_TTY
        COMPOSE_TTY=$(yq -r ".services.\"${SERVICE_NAME_ARG}\".tty // \"false\"" "$CONFIGURATION_FILE" 2>/dev/null || echo "false")
        if [ "$COMPOSE_TTY" = "true" ]; then
            ISSUES+=("compose: tty: true")
        fi
        local COMPOSE_PRIV
        COMPOSE_PRIV=$(yq -r ".services.\"${SERVICE_NAME_ARG}\".privileged // \"false\"" "$CONFIGURATION_FILE" 2>/dev/null || echo "false")
        if [ "$COMPOSE_PRIV" = "true" ]; then
            ISSUES+=("compose: privileged: true")
        fi
    fi

    # Final decision
    if [ "${#ISSUES[@]}" -gt 0 ]; then
        log_error "  ✗ UNSECURED: ${SERVICE_NAME_ARG} (${CID}) - issues detected:${NC}"
        for issue in "${ISSUES[@]}"; do
            log_error "    - ${issue}${NC}"
        done
        ((UNSECURED_COUNT++))
    else
        log_info "  ✓ SECURED: ${SERVICE_NAME_ARG} (${CID}) - no obvious runtime insecurities detected${NC}"
        ((SECURED_COUNT++))
    fi
}

#
# Function: install_yq
# Install yq if not present
#
install_yq() {
    log_info "yq is not installed. Installing yq..."
    
    # Detect OS and architecture
    local OS
    local ARCH
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # Convert architecture names
    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
    esac
    
    # Try to install via package manager first
    if command -v apt-get &> /dev/null; then
        log_debug "Installing yq via apt..."
        sudo apt-get update && sudo apt-get install -y yq
    elif command -v yum &> /dev/null; then
        log_debug "Installing yq via yum..."
        sudo yum install -y yq
    elif command -v brew &> /dev/null; then
        log_debug "Installing yq via brew..."
        brew install yq
    elif command -v pip3 &> /dev/null; then
        log_debug "Installing Python yq via pip3..."
        sudo pip3 install yq
    else
        log_error "Error: No supported package manager found (apt, yum, brew, or pip3)."
        log_error "Please install yq manually from: https://github.com/mikefarah/yq"
        exit 1
    fi
    
    # Verify installation
    if ! command -v yq &> /dev/null; then
        log_error "Error: yq installation failed."
        exit 1
    fi
    
    log_info "yq installed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --docker-compose)
            CONFIGURATION_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if docker-compose file parameter is provided
if [ -z "$CONFIGURATION_FILE" ]; then
    log_error "✗ Error: --docker-compose parameter is required"
    usage
fi

# Check if the file exists
if [ ! -f "$CONFIGURATION_FILE" ]; then
    log_error "✗ Error: File '$CONFIGURATION_FILE' does not exist"
    exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    install_yq
fi

log_info "================================================"
log_info "Docker Swarm Service Security Check"
log_info "================================================"
log_info "Configuration file: $CONFIGURATION_FILE"

# Extract all service names from the docker-compose file
SERVICES=$(yq -r '.services | keys[]' "$CONFIGURATION_FILE")

if [ -z "$SERVICES" ]; then
    log_error "✗ Error: No services found in the configuration file"
    exit 1
fi

# Count total services
TOTAL_SERVICES=$(echo "$SERVICES" | wc -l)

log_info "Found ${TOTAL_SERVICES} service(s) to check"
log_info "================================================"
log_info ""

# Check each service
while IFS= read -r SERVICE; do
    check_service_security "$SERVICE"
done <<< "$SERVICES"

# Display summary
log_info "================================================"
log_info "SECURITY CHECK SUMMARY"
log_info "================================================"
log_info "Total services checked: $((SECURED_COUNT + UNSECURED_COUNT))"
log_info "Secured services: ${SECURED_COUNT}${NC}"
log_warning "Unsecured services: ${UNSECURED_COUNT}${NC}"

if [ $UNSECURED_COUNT -eq 0 ]; then
    log_info "✓ All services are properly secured!${NC}"
    exit 0
else
    log_error "✗ Warning: Some services are not secured!${NC}"
    exit 1
fi