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
sudo dnf install -y docker

# Start and enable Docker
log "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

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

# Install other useful tools
log "Installing additional tools..."
sudo dnf install -y htop vim git unzip curl wget jq

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

# Configure firewall (firewalld on Amazon Linux)
log "Configuring firewall..."
sudo systemctl start firewalld
sudo systemctl enable firewalld
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
log "Firewall configured and enabled"

# Create shared Docker network
log "Creating Docker network..."
if sudo -u ec2-user docker network create mastra-test-network --driver bridge 2>/dev/null; then
    log "Docker network 'mastra-test-network' created"
else
    log "Docker network 'mastra-test-network' already exists or failed to create"
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

# Create a success marker file
echo "$(date '+%Y-%m-%d %H:%M:%S')" | sudo tee /home/ec2-user/.setup-completed
sudo chown ec2-user:ec2-user /home/ec2-user/.setup-completed

log "Instance setup completed successfully!"
log "Setup log available at: /home/ec2-user/setup.log"