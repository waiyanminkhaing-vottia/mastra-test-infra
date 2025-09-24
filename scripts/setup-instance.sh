#!/bin/bash

# Script to manually setup instance if user_data fails
# Usage: ./setup-instance.sh <instance-ip>

set -euo pipefail

INSTANCE_IP=${1:-${LIGHTSAIL_HOST:-}}
SSH_USER="${SSH_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-}"
SETUP_SCRIPT="${SETUP_SCRIPT:-terraform/user_data.sh}"

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to validate inputs
validate_inputs() {
    if [ -z "$INSTANCE_IP" ]; then
        log "ERROR: Instance IP not provided"
        echo "Usage: $0 <instance-ip>"
        echo "Or set LIGHTSAIL_HOST environment variable"
        exit 1
    fi

    if [ ! -f "$SETUP_SCRIPT" ]; then
        log "ERROR: Setup script not found: $SETUP_SCRIPT"
        exit 1
    fi
}

# Function to setup SSH options
get_ssh_options() {
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=60"
    if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
        ssh_opts="$ssh_opts -i $SSH_KEY"
    fi
    echo "$ssh_opts"
}

# Function to copy and execute setup script
setup_instance() {
    local ssh_opts
    ssh_opts=$(get_ssh_options)

    log "Copying setup script to instance..."
    if ! scp $ssh_opts "$SETUP_SCRIPT" "$SSH_USER@$INSTANCE_IP:/tmp/setup.sh"; then
        log "ERROR: Failed to copy setup script to instance"
        exit 1
    fi

    log "Executing setup script on instance..."
    if ! ssh $ssh_opts "$SSH_USER@$INSTANCE_IP" << 'EOF'
        set -euo pipefail

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Making setup script executable..."
        chmod +x /tmp/setup.sh

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running setup script..."
        sudo /tmp/setup.sh

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verifying Docker installation..."
        docker --version
        docker-compose --version || echo "Warning: docker-compose not found"

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking network existence..."
        if docker network ls --format "{{.Name}}" | grep -q "^mastra-test-network$"; then
            echo "Network mastra-test-network exists"
        else
            echo "Warning: Network mastra-test-network not found"
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Instance setup completed!"
EOF
    then
        log "ERROR: Failed to execute setup script on instance"
        exit 1
    fi
}

main() {
    log "Starting instance setup for $INSTANCE_IP..."

    validate_inputs
    setup_instance

    log "Instance setup completed successfully!"
}

main "$@"