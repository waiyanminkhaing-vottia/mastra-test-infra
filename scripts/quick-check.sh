#!/bin/bash

# Quick script to check Nginx and Docker on the current Lightsail instance
# Run this after deployment to verify services are working

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log "Quick Health Check - Nginx and Docker"
log "====================================="

# Try to get instance IP from Terraform
cd "$PROJECT_ROOT/terraform"
if [ ! -d ".terraform" ]; then
    error "Terraform not initialized. Run 'terraform init' first."
    exit 1
fi

INSTANCE_IP=$(terraform output -raw instance_public_ip 2>/dev/null)
if [ -z "$INSTANCE_IP" ]; then
    error "Cannot get instance IP from Terraform outputs"
    exit 1
fi

log "Testing instance: $INSTANCE_IP"

# Test external connectivity
log "Testing external HTTP connectivity..."
if curl -s --connect-timeout 10 "http://$INSTANCE_IP/health" | grep -q "healthy"; then
    echo "✅ Health endpoint responding"
else
    warn "⚠️  Health endpoint not responding or instance not ready"
fi

# Use the comprehensive check script
if [ -f "$PROJECT_ROOT/scripts/check-services.sh" ]; then
    log "Running comprehensive service check..."
    "$PROJECT_ROOT/scripts/check-services.sh" "$INSTANCE_IP"
else
    error "check-services.sh script not found"
fi