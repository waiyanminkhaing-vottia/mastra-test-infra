# Mastra Test Infrastructure

Development infrastructure for Mastra test environment using AWS Lightsail and Terraform with proper development workflows and SSH key management.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                AWS Lightsail                    │
│  ┌─────────────────────────────────────────┐   │
│  │        Amazon Linux 2023 Instance       │   │
│  │                                         │   │
│  │  ┌─────────────────────────────────┐   │   │
│  │  │            Nginx                │   │   │
│  │  │         (Port 80/443)           │   │   │
│  │  │                                 │   │   │
│  │  │  /         →  Port 3000        │   │   │
│  │  │  /sanden   →  Port 3001        │   │   │
│  │  │  /health   →  Health Check     │   │   │
│  │  └─────────────────────────────────┘   │   │
│  │                                         │   │
│  │  ┌───────────┐ ┌───────────┐          │   │
│  │  │ Main App  │ │Sanden App │          │   │
│  │  │  :3000    │ │  :3001    │          │   │
│  │  │(Next.js)  │ │(Next.js)  │          │   │
│  │  └───────────┘ └───────────┘          │   │
│  │                                         │   │
│  │  ┌─────────────────────────────────┐   │   │
│  │  │           PostgreSQL            │   │   │
│  │  │            :5432               │   │   │
│  │  └─────────────────────────────────┘   │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## URL Routing

| URL | Docker Port | Application |
|-----|-------------|-------------|
| `http://demo.vottia.me/` | 3000 | Main Next.js App |
| `http://demo.vottia.me/sanden` | 3001 | Sanden App |
| `http://demo.vottia.me/health` | - | Health Check Endpoint |

## 🚀 Quick Start for Development

### Prerequisites
- [Terraform](https://terraform.io) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/)
- [GitHub CLI](https://cli.github.com/) (optional, for automated setup)
- AWS account with Lightsail access

### 1. Development Setup

Run the automated setup script:
```bash
./scripts/setup-dev.sh
```

This will guide you through:
- Setting up GitHub secrets and variables
- Configuring the development environment
- Explaining the deployment process

### 2. GitHub Repository Configuration

**Secrets** (Settings > Secrets and variables > Actions):
- `AWS_ACCESS_KEY_ID` - Your AWS access key ID
- `AWS_SECRET_ACCESS_KEY` - Your AWS secret access key
- `POSTGRES_PASSWORD` - Password for PostgreSQL database

**Variables**:
- `AWS_REGION` - AWS region (default: ap-northeast-1)
- `POSTGRES_DB` - Main PostgreSQL database name
- `POSTGRES_USER` - PostgreSQL username
- `AGENT_POSTGRES_DB` - Agent PostgreSQL database name

### 3. Deploy Infrastructure

**Option A: GitHub Actions (Recommended)**
1. Go to Actions tab → "Deploy to Lightsail"
2. Click "Run workflow"
3. Infrastructure will be created with environment-based naming (dev-mastra-test-*)

**Option B: Local Deployment**
```bash
cd terraform
terraform init
terraform plan    # Preview changes
terraform apply   # Create infrastructure
terraform destroy # Delete everything
```

### 4. Get SSH Access

After deployment, copy SSH keys to another repository for team access:
```bash
./scripts/copy-keys-to-repo.sh /path/to/another/repo dev
```

This creates:
- `keys/dev/dev-mastra-test-private-key.pem` - SSH private key
- `keys/dev/dev-mastra-test-public-key.pub` - SSH public key
- `keys/dev/dev-connection-info.txt` - Connection instructions
- `keys/README.md` - Usage documentation

### 2. Configure DNS

After deployment:
1. Note the nameservers from terraform outputs
2. Configure nameservers at your domain registrar (e.g., Namecheap, GoDaddy)
3. Wait 5-30 minutes for DNS propagation

### 3. Deploy Applications

SSH into your instance and run your Next.js containers:

```bash
# SSH to instance
ssh -i ~/.ssh/mastra-key ec2-user@<INSTANCE_IP>

# Run main app (routes to /)
docker run -d -p 3000:3000 --name main-app your-main-nextjs-image

# Run sanden app (routes to /sanden)
docker run -d -p 3001:3000 --name sanden-app your-sanden-nextjs-image

# Verify containers
docker ps
```

## Infrastructure Details

### Lightsail Instance
- **Size**: 2 vCPU, 4 GB RAM, 80 GB SSD (`medium_2_0`)
- **OS**: Amazon Linux 2023 (ec2-user)
- **Region**: Configurable via `aws_region` variable

### Pre-installed Software
- **Docker & Docker Compose**
- **Nginx** (configured as reverse proxy)
- **Development tools**: git, vim, htop, curl, wget, jq
- **Route53 DNS**: Automatic hosted zone and A record creation

### Open Ports
- **22** (SSH)
- **80** (HTTP)
- **443** (HTTPS)
- **5432** (PostgreSQL)

### Nginx Configuration

The Nginx reverse proxy is automatically configured with:
- Path-based routing to Docker containers
- Security headers
- Health check endpoint
- WebSocket support for Next.js development

## Managing Applications

### View Container Status
```bash
docker ps -a
docker logs main-app
docker logs sanden-app
```

### Restart Applications
```bash
docker restart main-app
docker restart sanden-app
```

### Update Applications
```bash
# Pull new image
docker pull your-main-nextjs-image:latest

# Stop and remove old container
docker stop main-app && docker rm main-app

# Run updated container
docker run -d -p 3000:3000 --name main-app your-main-nextjs-image:latest
```

## Adding New Applications

To add a new Next.js application:

### 1. Update Nginx Configuration

SSH to instance and edit Nginx config:
```bash
sudo vim /etc/nginx/sites-available/nextjs-apps
```

Add new location block:
```nginx
# Route /new-app to port 3002
location /new-app {
    proxy_pass http://127.0.0.1:3002;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;
}
```

### 2. Reload Nginx
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 3. Deploy Container
```bash
docker run -d -p 3002:3000 --name new-app your-new-nextjs-image
```

### 4. Update README
Add the new route to the URL routing table above.

## Monitoring & Debugging

### Health Checks

**Quick Health Check:**
```bash
# Check all services automatically
./scripts/quick-check.sh
```

**Comprehensive Service Check:**
```bash
# Detailed check with instance IP and SSH key
./scripts/check-services.sh <INSTANCE_IP> [ssh-key-path]

# Or let it auto-detect from Terraform
./scripts/check-services.sh
```

**Manual Checks:**
```bash
# Application health endpoint
curl http://demo.vottia.me/health

# On the instance directly:
sudo systemctl status nginx docker
sudo docker ps
sudo nginx -t
```

### Log Files
- **Setup logs**: `/home/ec2-user/setup.log`
- **Nginx access**: `/var/log/nginx/access.log`
- **Nginx errors**: `/var/log/nginx/error.log`
- **Container logs**: `docker logs <container-name>`

### Common Issues

**1. Applications not accessible**
- Check DNS A record configuration
- Verify containers are running: `docker ps`
- Check Nginx status: `sudo systemctl status nginx`

**2. Container fails to start**
- Check port conflicts: `netstat -tulpn | grep :3000`
- Review container logs: `docker logs <container-name>`

**3. Nginx configuration errors**
- Test config: `sudo nginx -t`
- Check error logs: `sudo tail -f /var/log/nginx/error.log`

## Terraform Outputs

After deployment, you'll see these useful outputs:
- `instance_public_ip`: Static IP address
- `app_urls`: Direct URLs to your applications
- `dns_configuration`: DNS A record information
- `route53_info`: Hosted zone ID and nameservers for domain setup
- `docker_ports`: Port mapping reference
- `ssh_command`: Ready-to-use SSH command
- `health_check_command`: Health check script command
- `setup_command`: Manual setup script command

## Development Workflow

1. **Make infrastructure changes** → Push to main branch (auto-deploys)
2. **Update applications** → Build new images and update containers
3. **Add new apps** → Update Nginx config and deploy containers
4. **Test changes** → Use health endpoints and logs for debugging

## Cost Estimates

Monthly costs (ap-northeast-1 region):
- **Lightsail Medium**: ~$20/month
- **Static IP**: Free with Lightsail
- **Data Transfer**: 3TB included

Perfect for development and testing environments.

## 🗑️ Cleanup & Resource Deletion

### Option A: GitHub Actions
1. Go to Actions → "Manage Infrastructure"
2. Click "Run workflow"
3. Select action: `destroy`
4. The workflow will:
   - List all resources to be deleted
   - Destroy all infrastructure
   - Verify cleanup completion

### Option B: Local Cleanup
```bash
# Interactive script with confirmations
./scripts/cleanup-resources.sh

# Or directly with Terraform
cd terraform
terraform destroy
```

### What Gets Deleted
- ✅ Lightsail instance (stops all running containers)
- ✅ Static IP address
- ✅ SSH key pair
- ✅ Security group rules
- ✅ All associated data

**⚠️ Warning:** Destruction is permanent and cannot be undone!

## Troubleshooting Checklist

- [ ] DNS A record points to correct IP
- [ ] Containers are running (`docker ps`)
- [ ] Nginx is running (`sudo systemctl status nginx`)
- [ ] No port conflicts (`netstat -tulpn`)
- [ ] Firewall allows traffic (`sudo ufw status`)
- [ ] Check application logs (`docker logs <name>`)

---

## Support

For issues:
1. Check the troubleshooting section above
2. Review setup logs: `/home/ec2-user/setup.log`
3. Verify container and service status
4. Check GitHub Actions workflow logs