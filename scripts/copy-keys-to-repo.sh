#!/bin/bash

# Script to copy SSH keys to another repository for development use
# Usage: ./copy-keys-to-repo.sh <target-repo-path> [environment]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${2:-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if target repository path is provided
if [ -z "$1" ]; then
    error "Usage: $0 <target-repo-path> [environment]"
fi

TARGET_REPO="$1"

# Check if target repository exists
if [ ! -d "$TARGET_REPO" ]; then
    error "Target repository directory does not exist: $TARGET_REPO"
fi

# Check if target is a git repository
if [ ! -d "$TARGET_REPO/.git" ]; then
    error "Target directory is not a git repository: $TARGET_REPO"
fi

log "Starting SSH key copy process..."
log "Source: $PROJECT_ROOT/terraform"
log "Target: $TARGET_REPO"
log "Environment: $ENVIRONMENT"

# Navigate to terraform directory
cd "$PROJECT_ROOT/terraform"

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    warn "Terraform not initialized. Running terraform init..."
    terraform init
fi

# Get SSH keys from Terraform outputs
log "Retrieving SSH keys from Terraform outputs..."

if ! PRIVATE_KEY=$(terraform output -raw ssh_private_key 2>/dev/null); then
    error "Failed to get private key from Terraform outputs. Make sure infrastructure is deployed."
fi

if ! PUBLIC_KEY=$(terraform output -raw ssh_public_key 2>/dev/null); then
    error "Failed to get public key from Terraform outputs. Make sure infrastructure is deployed."
fi

if ! HOST_IP=$(terraform output -raw instance_public_ip 2>/dev/null); then
    error "Failed to get instance IP from Terraform outputs. Make sure infrastructure is deployed."
fi

# Create keys directory in target repository
KEYS_DIR="$TARGET_REPO/keys/$ENVIRONMENT"
mkdir -p "$KEYS_DIR"

# Save keys to target repository
PRIVATE_KEY_FILE="$KEYS_DIR/${ENVIRONMENT}-mastra-test-private-key.pem"
PUBLIC_KEY_FILE="$KEYS_DIR/${ENVIRONMENT}-mastra-test-public-key.pub"
CONNECTION_INFO_FILE="$KEYS_DIR/${ENVIRONMENT}-connection-info.txt"

log "Saving SSH keys to target repository..."

echo "$PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
echo "$PUBLIC_KEY" > "$PUBLIC_KEY_FILE"

# Set proper permissions
chmod 600 "$PRIVATE_KEY_FILE"
chmod 644 "$PUBLIC_KEY_FILE"

# Create connection info file
cat > "$CONNECTION_INFO_FILE" << EOF
# SSH Connection Information for $ENVIRONMENT environment
# Generated on: $(date)

Host IP: $HOST_IP
User: ec2-user
Private Key: ${ENVIRONMENT}-mastra-test-private-key.pem

# SSH Command:
ssh -i keys/$ENVIRONMENT/${ENVIRONMENT}-mastra-test-private-key.pem ec2-user@$HOST_IP

# SCP Command (upload file):
scp -i keys/$ENVIRONMENT/${ENVIRONMENT}-mastra-test-private-key.pem /local/file ec2-user@$HOST_IP:/remote/path

# SCP Command (download file):
scp -i keys/$ENVIRONMENT/${ENVIRONMENT}-mastra-test-private-key.pem ec2-user@$HOST_IP:/remote/file /local/path
EOF

# Create or update README
README_FILE="$TARGET_REPO/keys/README.md"
if [ ! -f "$README_FILE" ]; then
    cat > "$README_FILE" << 'EOF'
# SSH Keys Directory

This directory contains SSH keys for accessing Mastra test infrastructure.

## Security Notice
- These keys are for development purposes only
- Never commit these keys to version control
- Rotate keys regularly
- Use proper access controls

## Usage

### SSH Connection
```bash
ssh -i keys/dev/dev-mastra-test-private-key.pem ec2-user@<instance-ip>
```

### File Transfer
```bash
# Upload
scp -i keys/dev/dev-mastra-test-private-key.pem local-file ec2-user@<instance-ip>:/remote/path

# Download
scp -i keys/dev/dev-mastra-test-private-key.pem ec2-user@<instance-ip>:/remote/file ./local-path
```

## Environments
- `dev/` - Development environment keys
- `staging/` - Staging environment keys (if applicable)
- `prod/` - Production environment keys (if applicable)
EOF
fi

# Update .gitignore to exclude private keys
GITIGNORE_FILE="$TARGET_REPO/.gitignore"
if [ -f "$GITIGNORE_FILE" ]; then
    if ! grep -q "keys/.*\.pem" "$GITIGNORE_FILE"; then
        echo "" >> "$GITIGNORE_FILE"
        echo "# SSH Private Keys" >> "$GITIGNORE_FILE"
        echo "keys/**/*.pem" >> "$GITIGNORE_FILE"
        log "Updated .gitignore to exclude private keys"
    fi
else
    cat > "$GITIGNORE_FILE" << 'EOF'
# SSH Private Keys
keys/**/*.pem
EOF
    log "Created .gitignore to exclude private keys"
fi

log "SSH keys successfully copied to target repository!"
log "Files created:"
log "  - Private key: $PRIVATE_KEY_FILE"
log "  - Public key: $PUBLIC_KEY_FILE"
log "  - Connection info: $CONNECTION_INFO_FILE"
log "  - README: $README_FILE"

warn "Remember to:"
warn "  1. Never commit private keys to version control"
warn "  2. Share connection info securely with team members"
warn "  3. Rotate keys regularly"

log "SSH command: ssh -i $PRIVATE_KEY_FILE ec2-user@$HOST_IP"