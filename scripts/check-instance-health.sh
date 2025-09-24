#!/bin/bash

# Script to check instance health and Docker status
# Usage: ./check-instance-health.sh <instance-ip>

set -euo pipefail

INSTANCE_IP=${1:-${LIGHTSAIL_HOST:-}}
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"

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
}

# Function to setup SSH options
get_ssh_options() {
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=60"
    if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
        ssh_opts="$ssh_opts -i $SSH_KEY"
    fi
    echo "$ssh_opts"
}

# Function to run health checks
run_health_checks() {
    local ssh_opts
    ssh_opts=$(get_ssh_options)

    log "Running health checks on instance..."

    if ! ssh $ssh_opts "$SSH_USER@$INSTANCE_IP" << 'EOF'
        set -euo pipefail

        echo "=== System Info ==="
        uname -a
        uptime
        echo "Load average: $(cat /proc/loadavg)"

        echo -e "\n=== Disk Usage ==="
        df -h / /tmp /var/lib/docker 2>/dev/null || df -h

        echo -e "\n=== Memory Usage ==="
        free -h

        echo -e "\n=== Network Connectivity ==="
        ping -c 3 8.8.8.8 > /dev/null && echo "Internet connectivity: OK" || echo "Internet connectivity: FAILED"

        echo -e "\n=== Docker Status ==="
        if systemctl is-active docker --quiet; then
            echo "Docker service: Running"
            sudo systemctl status docker --no-pager -l --lines=5
        else
            echo "Docker service: Not running"
            exit 1
        fi

        echo -e "\n=== Docker Version ==="
        docker --version || echo "Docker command failed"
        docker-compose --version 2>/dev/null || echo "docker-compose not available"

        echo -e "\n=== Docker Networks ==="
        docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"

        echo -e "\n=== Running Containers ==="
        if [ "$(docker ps -q | wc -l)" -gt 0 ]; then
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        else
            echo "No running containers"
        fi

        echo -e "\n=== All Containers ==="
        if [ "$(docker ps -aq | wc -l)" -gt 0 ]; then
            docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
        else
            echo "No containers found"
        fi

        echo -e "\n=== Docker Images ==="
        if [ "$(docker images -q | wc -l)" -gt 0 ]; then
            docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
        else
            echo "No images found"
        fi

        echo -e "\n=== Docker System Info ==="
        docker system df

        echo -e "\n=== Docker Resource Usage ==="
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || echo "No running containers to show stats"

        echo -e "\n=== Recent System Logs ==="
        journalctl --no-pager --lines=10 --since "1 hour ago" | tail -10 2>/dev/null || echo "Unable to fetch recent logs"

        echo -e "\n=== Cloud-Init Logs ==="
        if [ -f /var/log/cloud-init-output.log ]; then
            tail -20 /var/log/cloud-init-output.log
        else
            echo "No cloud-init logs found"
        fi
EOF
    then
        log "ERROR: Health check failed"
        exit 1
    fi
}

main() {
    log "Starting health check for instance $INSTANCE_IP..."

    validate_inputs
    run_health_checks

    log "Health check completed successfully!"
}

main "$@"