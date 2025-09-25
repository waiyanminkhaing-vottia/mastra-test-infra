#!/bin/bash

# Development setup script for Mastra test infrastructure
# This script helps set up the development environment with proper GitHub secrets

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
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log "Mastra Test Infrastructure - Development Setup"
log "============================================="

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/terraform/main.tf" ]; then
    error "This script must be run from the project root or scripts directory"
fi

log "Project root: $PROJECT_ROOT"

# Check required tools
info "Checking required tools..."

command -v terraform >/dev/null 2>&1 || error "Terraform is not installed"
command -v aws >/dev/null 2>&1 || error "AWS CLI is not installed"
command -v gh >/dev/null 2>&1 || warn "GitHub CLI not found. You'll need to set secrets manually."

log "✅ Required tools check complete"

# GitHub repository setup
info "Setting up GitHub repository secrets..."

echo ""
echo "You need to configure the following GitHub secrets:"
echo "================================================="
echo ""
echo "Repository secrets (Settings > Secrets and variables > Actions):"
echo "1. AWS_ACCESS_KEY_ID     - Your AWS access key ID"
echo "2. AWS_SECRET_ACCESS_KEY - Your AWS secret access key"
echo "3. POSTGRES_PASSWORD     - Password for PostgreSQL database"
echo ""
echo "Repository variables (Settings > Secrets and variables > Actions):"
echo "1. AWS_REGION           - AWS region (default: ap-northeast-1)"
echo "2. POSTGRES_DB          - Main PostgreSQL database name"
echo "3. POSTGRES_USER        - PostgreSQL username"
echo "4. AGENT_POSTGRES_DB    - Agent PostgreSQL database name"
echo ""

# If GitHub CLI is available, offer to set secrets
if command -v gh >/dev/null 2>&1; then
    echo ""
    read -p "Do you want to set up GitHub secrets now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Setting up GitHub secrets..."

        # Check if we're in a git repository and logged into GitHub
        if ! gh auth status >/dev/null 2>&1; then
            warn "Please login to GitHub CLI first: gh auth login"
            exit 1
        fi

        # Set secrets
        read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
        read -s -p "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo
        read -s -p "Enter PostgreSQL Password: " POSTGRES_PASSWORD
        echo

        gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID"
        gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY"
        gh secret set POSTGRES_PASSWORD --body "$POSTGRES_PASSWORD"

        log "✅ GitHub secrets set successfully"

        # Set variables
        gh variable set AWS_REGION --body "ap-northeast-1"
        gh variable set POSTGRES_DB --body "mastra_db"
        gh variable set POSTGRES_USER --body "postgres"
        gh variable set AGENT_POSTGRES_DB --body "agent_db"

        log "✅ GitHub variables set successfully"
    fi
fi

echo ""
log "Development environment setup information:"
log "=========================================="
echo ""
echo "1. Terraform Configuration:"
echo "   - Environment: dev"
echo "   - Project: mastra-test"
echo "   - Resources will be named: dev-mastra-test-*"
echo ""
echo "2. Deployment:"
echo "   - Run workflow: 'Deploy to Lightsail' in GitHub Actions"
echo "   - Or manually: cd terraform && terraform init && terraform plan && terraform apply"
echo ""
echo "3. SSH Access:"
echo "   - After deployment, use the 'copy-keys-to-repo.sh' script"
echo "   - Example: ./scripts/copy-keys-to-repo.sh /path/to/another/repo dev"
echo ""
echo "4. Accessing Services:"
echo "   - SSH: Available after running copy-keys-to-repo.sh"
echo "   - PostgreSQL: Port 5432 (accessible from SSH tunnel)"
echo "   - Web Apps: Port 80/443 via Nginx reverse proxy"
echo ""

warn "Security Reminders:"
warn "=================="
echo "1. These are development credentials - never use in production"
echo "2. Rotate credentials regularly"
echo "3. Never commit SSH private keys to version control"
echo "4. Use GitHub's secret scanning to detect accidental key exposure"

echo ""
log "Setup complete! You can now run the GitHub Actions workflow to deploy."