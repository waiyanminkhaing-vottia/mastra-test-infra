#!/bin/bash

# Script to check if Nginx and Docker are working properly on Lightsail instance
# Usage: ./check-services.sh [instance-ip] [ssh-key-path]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to get instance IP from Terraform
get_instance_ip() {
    cd "$PROJECT_ROOT/terraform"
    if [ -d ".terraform" ]; then
        terraform output -raw instance_public_ip 2>/dev/null || echo ""
    fi
}

# Function to get SSH key from Terraform
get_ssh_key() {
    cd "$PROJECT_ROOT/terraform"
    if [ -d ".terraform" ]; then
        terraform output -raw ssh_private_key 2>/dev/null || echo ""
    fi
}

# Parse command line arguments
INSTANCE_IP="$1"
SSH_KEY_PATH="$2"

# If no IP provided, try to get from Terraform
if [ -z "$INSTANCE_IP" ]; then
    INSTANCE_IP=$(get_instance_ip)
    if [ -z "$INSTANCE_IP" ]; then
        error "Instance IP not provided and cannot be retrieved from Terraform"
        echo "Usage: $0 [instance-ip] [ssh-key-path]"
        exit 1
    fi
    info "Using instance IP from Terraform: $INSTANCE_IP"
fi

# If no SSH key provided, try to get from Terraform and save to temp file
if [ -z "$SSH_KEY_PATH" ]; then
    SSH_KEY_CONTENT=$(get_ssh_key)
    if [ -n "$SSH_KEY_CONTENT" ]; then
        SSH_KEY_PATH="/tmp/temp-ssh-key.pem"
        echo "$SSH_KEY_CONTENT" > "$SSH_KEY_PATH"
        chmod 600 "$SSH_KEY_PATH"
        info "Using SSH key from Terraform (saved to temp file)"
    else
        error "SSH key path not provided and cannot be retrieved from Terraform"
        echo "Usage: $0 [instance-ip] [ssh-key-path]"
        exit 1
    fi
fi

# Verify SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    error "SSH key file not found: $SSH_KEY_PATH"
    exit 1
fi

log "Starting service health check for $INSTANCE_IP"
log "=========================================="

# Test SSH connectivity first
info "Testing SSH connectivity..."
if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ec2-user@"$INSTANCE_IP" "echo 'SSH connection successful'" >/dev/null 2>&1; then
    success "✅ SSH connection working"
else
    error "❌ SSH connection failed"
    exit 1
fi

# Function to run remote command
run_remote() {
    ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ec2-user@"$INSTANCE_IP" "$1" 2>/dev/null
}

# Check Docker installation and service
info "Checking Docker..."
echo "=================="

if run_remote "command -v docker" >/dev/null; then
    success "✅ Docker is installed"

    DOCKER_VERSION=$(run_remote "docker --version" | cut -d' ' -f3 | sed 's/,//')
    info "Docker version: $DOCKER_VERSION"

    # Check Docker service status
    if run_remote "sudo systemctl is-active docker" | grep -q "active"; then
        success "✅ Docker service is running"
    else
        warn "⚠️  Docker service is not running"
        info "Attempting to start Docker service..."
        if run_remote "sudo systemctl start docker"; then
            success "✅ Docker service started successfully"
        else
            error "❌ Failed to start Docker service"
        fi
    fi

    # Check Docker permissions
    if run_remote "docker ps" >/dev/null 2>&1; then
        success "✅ Docker permissions working (no sudo needed)"
    elif run_remote "sudo docker ps" >/dev/null 2>&1; then
        warn "⚠️  Docker requires sudo (user not in docker group or session needs refresh)"
        info "Docker containers:"
        run_remote "sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    else
        error "❌ Docker not accessible"
    fi

    # Check Docker network
    if run_remote "sudo docker network ls | grep -q mastra-test-network"; then
        success "✅ Docker network 'mastra-test-network' exists"
    else
        warn "⚠️  Docker network 'mastra-test-network' not found"
    fi

else
    error "❌ Docker is not installed"
    exit 1
fi

echo ""
info "Checking Nginx..."
echo "================="

if run_remote "command -v nginx" >/dev/null; then
    success "✅ Nginx is installed"

    NGINX_VERSION=$(run_remote "nginx -v 2>&1 | cut -d' ' -f3")
    info "Nginx version: $NGINX_VERSION"

    # Check Nginx service status
    if run_remote "sudo systemctl is-active nginx" | grep -q "active"; then
        success "✅ Nginx service is running"
    else
        warn "⚠️  Nginx service is not running"
        info "Attempting to start Nginx service..."
        if run_remote "sudo systemctl start nginx"; then
            success "✅ Nginx service started successfully"
        else
            error "❌ Failed to start Nginx service"
        fi
    fi

    # Check Nginx configuration
    if run_remote "sudo nginx -t" >/dev/null 2>&1; then
        success "✅ Nginx configuration is valid"
    else
        error "❌ Nginx configuration has errors"
        run_remote "sudo nginx -t"
    fi

    # Check if Nginx is listening on ports
    if run_remote "sudo netstat -tlnp | grep ':80 '" | grep -q nginx; then
        success "✅ Nginx is listening on port 80"
    else
        warn "⚠️  Nginx is not listening on port 80"
    fi

    if run_remote "sudo netstat -tlnp | grep ':443 '" | grep -q nginx 2>/dev/null; then
        success "✅ Nginx is listening on port 443"
    else
        info "ℹ️  Nginx is not configured for HTTPS (port 443)"
    fi

else
    error "❌ Nginx is not installed"
fi

echo ""
info "Testing HTTP endpoints..."
echo "========================="

# Test health endpoint
info "Testing health endpoint..."
if curl -s --connect-timeout 5 "http://$INSTANCE_IP/health" | grep -q "healthy"; then
    success "✅ Health endpoint is working"
else
    warn "⚠️  Health endpoint not responding properly"
fi

# Test if any applications are running on expected ports
info "Checking application ports..."
if run_remote "sudo netstat -tlnp | grep ':3000 '" >/dev/null; then
    success "✅ Application running on port 3000"
else
    info "ℹ️  No application running on port 3000"
fi

if run_remote "sudo netstat -tlnp | grep ':3001 '" >/dev/null; then
    success "✅ Application running on port 3001"
else
    info "ℹ️  No application running on port 3001"
fi

echo ""
info "System Information..."
echo "===================="

# System resources
UPTIME=$(run_remote "uptime")
MEMORY=$(run_remote "free -h | grep Mem")
DISK=$(run_remote "df -h | grep -E '^/dev/' | head -1")

info "System uptime: $UPTIME"
info "Memory: $MEMORY"
info "Disk: $DISK"

# Check if setup completed
if run_remote "[ -f /home/ec2-user/.setup-completed ]"; then
    SETUP_DATE=$(run_remote "cat /home/ec2-user/.setup-completed")
    success "✅ Instance setup completed at: $SETUP_DATE"
else
    warn "⚠️  Setup completion marker not found"
    if run_remote "[ -f /home/ec2-user/setup.log ]"; then
        info "Setup log exists. Last 5 lines:"
        run_remote "tail -5 /home/ec2-user/setup.log"
    fi
fi

echo ""
log "Health check completed!"
log "======================="

# Summary
echo ""
info "Quick Summary:"
run_remote "sudo systemctl is-active docker nginx" | while read service status; do
    if [ "$status" = "active" ]; then
        success "✅ $service: $status"
    else
        warn "⚠️  $service: $status"
    fi
done

# Cleanup temp SSH key if created
if [[ "$SSH_KEY_PATH" == "/tmp/temp-ssh-key.pem" ]]; then
    rm -f "$SSH_KEY_PATH"
fi

log "Use './scripts/check-services.sh $INSTANCE_IP [key-path]' to run this check again"