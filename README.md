# Mastra Test Infrastructure

A comprehensive infrastructure setup for deploying applications on AWS Lightsail with dynamic nginx route management and private Docker registry.

## 🏗️ Architecture

- **AWS Lightsail Instance** - Amazon Linux 2023
- **Docker & Docker Compose** - Container orchestration
- **Nginx** - Reverse proxy with dynamic route management
- **Private Docker Registry** - SSH-tunnel accessible only
- **PostgreSQL** - Database with pgvector extension
- **Terraform** - Infrastructure as Code
- **GitHub Actions** - CI/CD and route management

## 🚀 Quick Start

### 1. Deploy Infrastructure

```bash
# Go to GitHub Actions → "Manage Infrastructure"
# Select Action: "apply"
```

This will create:
- Lightsail instance with static IP
- Route53 DNS record
- Security groups and firewall rules
- Docker registry (SSH-tunnel only)
- Nginx with basic configuration

### 2. Manage Routes Dynamically

```bash
# Go to GitHub Actions → "Manage Nginx Routes"
# Add a health check:
Action: add
Route Name: health
Route Path: /health
Route Type: health

# Add API service:
Action: add
Route Name: api-service
Route Path: /api
Target Port: 3001
Route Type: proxy
```

## 📁 Project Structure

```
├── .github/workflows/
│   ├── infrastructure.yml    # Main infrastructure deployment
│   ├── deploy.yml           # Application deployment
│   └── manage-routes.yml    # Dynamic nginx route management
├── terraform/
│   ├── main.tf              # Lightsail infrastructure
│   ├── variables.tf         # Configuration variables
│   ├── outputs.tf           # Infrastructure outputs
│   └── user_data.sh         # Instance initialization script
├── nginx-routes.json        # Dynamic route configuration
├── docker-compose.yml       # Local development services
└── README.md               # This file
```

## 🛠️ Infrastructure Components

### Lightsail Instance
- **OS**: Amazon Linux 2023
- **Bundle**: Configurable (default: nano_2_0)
- **Ports**: 22 (SSH), 80 (HTTP), 443 (HTTPS), 5432 (PostgreSQL)
- **Storage**: Persistent volumes for Docker registry and database

### Docker Services
- **Docker Engine** - Latest version
- **Docker Compose** - For multi-container applications
- **Private Registry** - Accessible via SSH tunnel on port 5000
- **Network**: `mastra-test-network` bridge network

### Nginx Configuration
- **Dynamic Routes** - Managed via GitHub Actions
- **Security Headers** - OWASP recommended headers
- **Health Checks** - Built-in monitoring endpoints
- **Backup System** - Automatic configuration backups

## 🔧 Configuration

### Required GitHub Secrets
```
AWS_ACCESS_KEY_ID       # AWS access key
AWS_SECRET_ACCESS_KEY   # AWS secret key
```

### Required GitHub Variables
```
AWS_REGION             # AWS region (default: ap-northeast-1)
```

### Terraform Variables
Edit `terraform/variables.tf` to customize:
- Instance bundle size
- Domain configuration
- Environment settings

## 🌐 Dynamic Route Management

### Available Route Types

#### Proxy Routes
Route requests to local applications:
```json
{
  "name": "api-service",
  "path": "/api",
  "type": "proxy",
  "target_port": "3001"
}
```

#### Health Checks
Simple health monitoring endpoints:
```json
{
  "name": "health",
  "path": "/health",
  "type": "health"
}
```

#### Redirects
HTTP redirections:
```json
{
  "name": "redirect-home",
  "path": "/old-path",
  "type": "redirect",
  "redirect_url": "/"
}
```

### Route Operations

| Operation | Description | Required Fields |
|-----------|-------------|----------------|
| `list` | Show current routes | None |
| `add` | Create new route | route_name, route_path, route_type |
| `remove` | Delete route | route_name |
| `update` | Modify route | route_name + fields to update |
| `reload` | Regenerate config | None |

## 🐳 Docker Registry Usage

The private Docker registry is only accessible via SSH tunnel for security.

### Setup SSH Tunnel
```bash
ssh -L 5000:localhost:5000 -i /path/to/ssh-key ec2-user@<instance-ip>
```

### Use Registry
```bash
# Tag image
docker tag my-app:latest localhost:5000/my-app:latest

# Push to registry
docker push localhost:5000/my-app:latest

# Pull from registry
docker pull localhost:5000/my-app:latest
```

## 🗄️ Database

PostgreSQL with pgvector extension for vector operations.

### Connection Details
```bash
Host: <instance-ip>
Port: 5432
Database: ${POSTGRES_DB}
User: ${POSTGRES_USER}
Password: ${POSTGRES_PASSWORD}
```

### Local Development
```bash
docker-compose up postgres
```

## 🚀 Deployment Workflow

### 1. Infrastructure Deployment
```bash
# Via GitHub Actions
Actions → "Manage Infrastructure" → Run workflow → Action: "apply"

# Via Terraform (local)
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Application Deployment
```bash
# Via GitHub Actions
Actions → "Deploy Application" → Run workflow
```

### 3. Route Management
```bash
# Via GitHub Actions
Actions → "Manage Nginx Routes" → Run workflow
```

## 🔍 Monitoring & Debugging

### Check Infrastructure Status
```bash
# Via GitHub Actions workflow logs
# Or SSH into instance:
ssh -i /path/to/key ec2-user@<instance-ip>

# Check services
sudo systemctl status nginx
sudo systemctl status docker
docker ps

# Check logs
sudo journalctl -u nginx -f
docker logs <container-name>
```

### Verify Routes
```bash
# Test health endpoint
curl http://<instance-ip>/health

# Test specific route
curl http://<instance-ip>/api/status
```

## 🛡️ Security Features

- **SSH Key Authentication** - No password access
- **Firewall Configuration** - Only required ports open
- **Private Registry** - SSH tunnel access only
- **Security Headers** - OWASP recommended nginx headers
- **Configuration Backups** - Automatic backup before changes
- **Git Tracking** - All configuration changes versioned

## 🔄 Backup & Recovery

### Infrastructure Backup
- Terraform state is managed remotely
- Configuration files are version controlled
- Automatic nginx configuration backups

### Emergency Recovery
```bash
# Restore nginx configuration
ssh ec2-user@<instance-ip>
sudo cp /etc/nginx/conf.d/nextjs-apps.conf.backup.* /etc/nginx/conf.d/nextjs-apps.conf
sudo systemctl reload nginx

# Rebuild infrastructure
terraform destroy
terraform apply
```

## 📚 Documentation

- **Route Management** - See "Dynamic Route Management" section above
- **Terraform Documentation** - See `terraform/` directory
- **GitHub Actions** - See `.github/workflows/` directory

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Test with `terraform plan`
5. Submit a pull request

## 📄 License

This infrastructure configuration is provided as-is for the Mastra project.

## 🆘 Support

For issues and questions:
1. Check GitHub Actions workflow logs
2. Review server logs via SSH
3. Check Terraform state and outputs
4. Refer to documentation in this repository

---

**Last Updated**: January 2025
**Infrastructure Version**: 1.0
**Terraform Version**: >= 1.0