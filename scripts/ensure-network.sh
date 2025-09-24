#!/bin/bash

# Script to ensure shared Docker network exists
# This should be run by each service deployment

set -euo pipefail

NETWORK_NAME="${NETWORK_NAME:-mastra-test-network}"

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log "ERROR: Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log "ERROR: Docker daemon is not running or not accessible"
        exit 1
    fi
}

main() {
    log "Checking Docker availability..."
    check_docker

    log "Ensuring network '$NETWORK_NAME' exists..."

    # Check if network exists
    if ! docker network ls --format "{{.Name}}" | grep -q "^${NETWORK_NAME}$"; then
        log "Creating shared network: $NETWORK_NAME"
        if docker network create "$NETWORK_NAME" --driver bridge; then
            log "Successfully created network: $NETWORK_NAME"
        else
            log "ERROR: Failed to create network: $NETWORK_NAME"
            exit 1
        fi
    else
        log "Network $NETWORK_NAME already exists"
    fi

    log "Network $NETWORK_NAME is ready"
}

main "$@"