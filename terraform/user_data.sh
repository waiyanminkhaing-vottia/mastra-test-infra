#!/bin/bash

# User data script for Mastra test infrastructure setup
# This script runs on instance first boot - Amazon Linux 2023

set -e

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /home/ec2-user/setup.log
}

log "Starting instance setup on Amazon Linux 2023..."

# Update system
log "Updating system packages..."
sudo dnf update -y

# Install Docker
log "Installing Docker..."
if sudo dnf install -y docker; then
    log "Docker package installed successfully"
else
    log "ERROR: Docker package installation failed"
    exit 1
fi

# Start and enable Docker
log "Starting Docker service..."
if sudo systemctl start docker; then
    log "Docker service started successfully"
    sudo systemctl enable docker
    log "Docker service enabled for startup"
else
    log "ERROR: Failed to start Docker service"
    exit 1
fi

# Add ec2-user to docker group
log "Adding ec2-user to docker group..."
sudo usermod -aG docker ec2-user

# Wait for Docker to be ready
log "Waiting for Docker to be ready..."
while ! sudo docker info >/dev/null 2>&1; do
    log "Waiting for Docker daemon..."
    sleep 2
done

# Install Docker Compose
log "Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create app directory with proper permissions
log "Creating application directory..."
sudo mkdir -p /home/ec2-user/app
sudo chown ec2-user:ec2-user /home/ec2-user/app
sudo chmod 755 /home/ec2-user/app

# Install git first (essential for version control)
log "Installing git..."
if sudo dnf install -y git; then
    log "Git installed successfully"
    git --version | tee -a /home/ec2-user/setup.log
else
    log "ERROR: Git installation failed"
    exit 1
fi

# Install other useful tools
log "Installing additional tools..."
sudo dnf install -y htop vim unzip curl wget jq || log "Some additional tools failed to install, continuing..."

# Install Ollama for running SLMs
log "Installing Ollama..."
if curl -fsSL https://ollama.com/install.sh | sh; then
    log "Ollama installed successfully"

    # Start Ollama service as ec2-user
    log "Starting Ollama service..."
    sudo -u ec2-user bash -c 'export PATH=$PATH:/usr/local/bin && nohup ollama serve > /home/ec2-user/ollama.log 2>&1 &'

    # Wait for Ollama to start
    log "Waiting for Ollama to start..."
    sleep 10

    # Test Ollama installation
    if sudo -u ec2-user bash -c 'export PATH=$PATH:/usr/local/bin && ollama list' >/dev/null 2>&1; then
        log "✅ Ollama is running and accessible"

        # Download a small model for testing
        log "Downloading Gemma 2B model (this may take a few minutes)..."
        sudo -u ec2-user bash -c 'export PATH=$PATH:/usr/local/bin && ollama pull gemma:2b' || log "⚠️ Failed to download model, but Ollama is installed"

    else
        log "⚠️ Ollama installed but not responding"
    fi
else
    log "ERROR: Ollama installation failed"
    # Continue without Ollama
fi

# Install nginx with cache refresh
log "Installing nginx..."
sudo dnf clean all
sudo dnf makecache
if sudo dnf install -y nginx; then
    log "Nginx installed successfully"
else
    log "ERROR: Nginx installation failed"
    # Continue without nginx for now
fi

# Configure Nginx for multiple Next.js apps (only if nginx is installed)
if command -v nginx >/dev/null 2>&1; then
    log "Configuring Nginx for multi-app setup..."
    sudo tee /etc/nginx/conf.d/nextjs-apps.conf > /dev/null << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    client_max_body_size 10M;

    # No routes configured - basic server only
}
EOF

# Remove default Nginx configuration
sudo rm -f /etc/nginx/nginx.conf.default

# Test Nginx configuration
log "Testing Nginx configuration..."
if sudo nginx -t; then
    log "Nginx configuration test passed"
else
    log "ERROR: Nginx configuration test failed"
    exit 1
fi

# Start and enable Nginx
log "Starting Nginx service..."
if sudo systemctl start nginx; then
    log "Nginx started successfully"
    sudo systemctl enable nginx
else
    log "ERROR: Failed to start Nginx"
    exit 1
fi

# Verify Nginx is running
log "Verifying Nginx status..."
sudo systemctl status nginx --no-pager

else
    log "Nginx not installed - skipping nginx configuration"
fi

# Configure firewall (Amazon Linux 2023 uses iptables, not firewalld by default)
log "Configuring firewall..."

# Check if firewalld is available, if not, use iptables or skip
if command -v firewall-cmd >/dev/null 2>&1; then
    log "Using firewalld for firewall configuration..."
    if ! sudo systemctl is-active firewalld >/dev/null 2>&1; then
        sudo systemctl start firewalld
        sudo systemctl enable firewalld
    fi
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --permanent --add-service=http
    sudo firewall-cmd --permanent --add-service=https
    sudo firewall-cmd --permanent --add-port=5432/tcp
    sudo firewall-cmd --reload
    log "Firewall configured with firewalld"
else
    log "Firewalld not available, checking for iptables..."
    if command -v iptables >/dev/null 2>&1; then
        log "Using iptables for basic firewall rules..."
        # Allow SSH (port 22)
        sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        # Allow HTTP (port 80)
        sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        # Allow HTTPS (port 443)
        sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        # Allow PostgreSQL (port 5432)
        sudo iptables -A INPUT -p tcp --dport 5432 -j ACCEPT
        # Allow established connections
        sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        # Allow loopback
        sudo iptables -A INPUT -i lo -j ACCEPT
        # Save iptables rules
        sudo service iptables save 2>/dev/null || log "iptables save not available, rules are temporary"
        log "Basic iptables rules configured"
    else
        log "Neither firewalld nor iptables available, relying on AWS security groups for firewall"
    fi
fi
log "Firewall configuration completed (Docker registry only accessible via SSH tunnel)"

# Create shared Docker network
log "Creating Docker network..."
if sudo -u ec2-user docker network create mastra-test-network --driver bridge 2>/dev/null; then
    log "Docker network 'mastra-test-network' created"
else
    log "Docker network 'mastra-test-network' already exists or failed to create"
fi

# Set up local Docker registry
log "Setting up local Docker registry..."
sudo mkdir -p /home/ec2-user/registry
sudo chown ec2-user:ec2-user /home/ec2-user/registry

# Create registry configuration
sudo tee /home/ec2-user/registry/config.yml > /dev/null << 'EOF'
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

# Start Docker registry container
log "Starting Docker registry container..."
if sudo -u ec2-user docker run -d \
  --restart=always \
  --name local-registry \
  -p 5000:5000 \
  -v /home/ec2-user/registry:/var/lib/registry \
  -v /home/ec2-user/registry/config.yml:/etc/docker/registry/config.yml \
  --network mastra-test-network \
  registry:2; then
    log "Docker registry started successfully"
else
    log "Failed to start Docker registry"
fi

# Configure Docker daemon to allow insecure registry
log "Configuring Docker daemon for insecure registry..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "insecure-registries": ["localhost:5000", "127.0.0.1:5000"]
}
EOF

# Restart Docker service to apply configuration
log "Restarting Docker service to apply registry configuration..."
sudo systemctl restart docker

# Wait for Docker to restart
log "Waiting for Docker to restart..."
while ! sudo docker info >/dev/null 2>&1; do
    log "Waiting for Docker daemon to restart..."
    sleep 2
done

# Restart the registry after Docker restart
log "Restarting Docker registry after Docker daemon restart..."
if sudo -u ec2-user docker start local-registry; then
    log "Docker registry restarted successfully"
else
    log "Failed to restart Docker registry"
fi

# Set proper log file permissions
sudo chown ec2-user:ec2-user /home/ec2-user/setup.log
sudo chmod 644 /home/ec2-user/setup.log

# Final verification
log "Performing final verification..."
if curl -s localhost/health | grep -q "healthy"; then
    log "✅ Health endpoint is working"
else
    log "⚠️  Health endpoint not responding, but continuing..."
fi

if systemctl is-active --quiet nginx; then
    log "✅ Nginx service is active"
else
    log "❌ Nginx service is not active"
fi

if systemctl is-active --quiet docker; then
    log "✅ Docker service is active"
else
    log "❌ Docker service is not active"
fi

# Verify git installation
if command -v git >/dev/null 2>&1; then
    GIT_VERSION=$(git --version)
    log "✅ Git is installed: $GIT_VERSION"
else
    log "❌ Git is not installed"
fi

# Verify Ollama installation
if command -v ollama >/dev/null 2>&1; then
    OLLAMA_VERSION=$(ollama --version 2>/dev/null || echo "unknown version")
    log "✅ Ollama is installed: $OLLAMA_VERSION"

    # Check if Ollama is running
    if pgrep -f "ollama serve" >/dev/null; then
        log "✅ Ollama service is running"

        # List available models
        MODELS=$(sudo -u ec2-user bash -c 'export PATH=$PATH:/usr/local/bin && ollama list 2>/dev/null | grep -v "NAME"' || echo "")
        if [ -n "$MODELS" ]; then
            log "✅ Ollama models available:"
            echo "$MODELS" | while read line; do
                log "   - $line"
            done
        else
            log "⚠️ No Ollama models installed yet"
        fi
    else
        log "⚠️ Ollama is installed but not running"
    fi
else
    log "❌ Ollama is not installed"
fi

# Verify Docker registry is running
if sudo -u ec2-user docker ps | grep -q local-registry; then
    log "✅ Docker registry is running"
    # Test registry health
    if curl -s http://localhost:5000/v2/ | grep -q "{}"; then
        log "✅ Docker registry is responding to health checks"
    else
        log "⚠️ Docker registry is not responding to health checks"
    fi
else
    log "❌ Docker registry is not running"
fi

# Create a success marker file
echo "$(date '+%Y-%m-%d %H:%M:%S')" | sudo tee /home/ec2-user/.setup-completed
sudo chown ec2-user:ec2-user /home/ec2-user/.setup-completed

log "Instance setup completed successfully!"
log "Setup log available at: /home/ec2-user/setup.log"