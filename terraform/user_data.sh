#!/bin/bash

# User data script for Mastra test infrastructure setup
# This script runs on instance first boot

set -eu

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /home/ubuntu/setup.log
}

log "Starting instance setup..."

# Update system
log "Updating system packages..."
sudo apt-get update -y

# Install Docker
log "Installing Docker dependencies..."
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings

log "Adding Docker GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

log "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

log "Installing Docker..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
log "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Add ubuntu user to docker group
log "Adding ubuntu user to docker group..."
sudo usermod -aG docker ubuntu

# Wait for Docker to be ready
log "Waiting for Docker to be ready..."
while ! sudo docker info >/dev/null 2>&1; do
    log "Waiting for Docker daemon..."
    sleep 2
done

# Install Docker Compose (standalone)
log "Installing Docker Compose standalone..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -n "$DOCKER_COMPOSE_VERSION" ]; then
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log "Docker Compose $DOCKER_COMPOSE_VERSION installed"
else
    log "Warning: Could not determine latest Docker Compose version, using fallback"
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Create app directory with proper permissions
log "Creating application directory..."
sudo mkdir -p /home/ubuntu/app
sudo chown ubuntu:ubuntu /home/ubuntu/app
sudo chmod 755 /home/ubuntu/app

# Install Nginx and other useful tools
log "Installing Nginx and additional tools..."
sudo apt-get install -y nginx htop vim git unzip curl wget jq

# Configure Nginx for multiple Next.js apps
log "Configuring Nginx for multi-app setup..."
sudo tee /etc/nginx/sites-available/nextjs-apps > /dev/null << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    client_max_body_size 10M;

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Route /sanden to port 3001
    location /sanden {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Default route - everything else goes to port 3000
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Remove default Nginx site and enable our configuration
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/nextjs-apps /etc/nginx/sites-enabled/

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

# Setup firewall with more restrictive rules
log "Configuring firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw allow 5432/tcp comment 'PostgreSQL'
# Rate limit SSH to prevent brute force attacks
sudo ufw limit ssh/tcp
sudo ufw --force enable
log "Firewall configured and enabled"

# Create shared Docker network
log "Creating Docker network..."
if sudo -u ubuntu docker network create mastra-test-network --driver bridge 2>/dev/null; then
    log "Docker network 'mastra-test-network' created"
else
    log "Docker network 'mastra-test-network' already exists or failed to create"
fi

# Set proper log file permissions
sudo chown ubuntu:ubuntu /home/ubuntu/setup.log
sudo chmod 644 /home/ubuntu/setup.log

# Create a success marker file
echo "$(date '+%Y-%m-%d %H:%M:%S')" | sudo tee /home/ubuntu/.setup-completed
sudo chown ubuntu:ubuntu /home/ubuntu/.setup-completed

log "Instance setup completed successfully!"
log "Setup log available at: /home/ubuntu/setup.log"