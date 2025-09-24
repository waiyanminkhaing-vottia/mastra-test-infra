#!/bin/bash

# Script to cleanup/destroy all infrastructure resources
# Usage: ./scripts/cleanup-resources.sh

set -euo pipefail

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to confirm destruction
confirm_destroy() {
    echo "⚠️  WARNING: This will permanently destroy all infrastructure resources!"
    echo "This includes:"
    echo "  - Lightsail instance"
    echo "  - Static IP address"
    echo "  - SSH key pair"
    echo "  - Security group rules"
    echo ""
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " confirm

    if [ "$confirm" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Function to destroy resources
destroy_resources() {
    log "Changing to terraform directory..."
    cd terraform

    log "Initializing Terraform..."
    terraform init

    log "Planning destruction..."
    terraform plan -destroy

    echo ""
    read -p "Proceed with destruction? (Type 'DESTROY' to confirm): " final_confirm

    if [ "$final_confirm" != "DESTROY" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi

    log "Destroying all resources..."
    terraform destroy -auto-approve

    log "✅ All resources have been destroyed!"
    log "Your AWS account will no longer be charged for these resources."
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."

    if terraform show -json | jq -e '.values.root_module.resources | length == 0' >/dev/null 2>&1; then
        log "✅ Verification successful - no resources remain"
    else
        log "⚠️  Warning: Some resources may still exist"
        log "Please check your AWS Lightsail console manually"
    fi
}

main() {
    log "Starting infrastructure cleanup..."

    confirm_destroy
    destroy_resources
    verify_cleanup

    log "🎉 Infrastructure cleanup completed!"
}

main "$@"