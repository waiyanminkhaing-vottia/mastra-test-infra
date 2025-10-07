# Mastra Test Infrastructure

A comprehensive infrastructure setup for deploying applications on AWS Lightsail with dynamic nginx route management and private Docker registry.

## 🏗️ Architecture

- **AWS Lightsail Instance** - Amazon Linux 2023
- **Docker & Docker Compose** - Container orchestration
- **Nginx** - Reverse proxy with dynamic route management and HTTPS support
- **Let's Encrypt SSL** - Automatic HTTPS certificates with auto-renewal
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

### 2. Setup HTTPS (One-time)

```bash
# Go to GitHub Actions → "Setup HTTPS/SSL"
# Install SSL certificate:
Domain: test.dev-maestra.vottia.me
Email: your-email@example.com
Action: install
```

This will:
- Install Certbot and obtain free SSL certificate from Let's Encrypt
- Configure automatic renewal (daily check at 12:00)
- Enable HTTPS on all routes automatically

### 3. Manage Routes Dynamically

```bash
# Go to GitHub Actions → "Manage Nginx Routes"
# Add API service:
Action: add
Route Name: api-service
Route Path: /api
Target Port: 3001
Route Type: normal

# Add Next.js app with basePath:
Action: add
Route Name: dashboard
Route Path: /dashboard
Target Port: 3000
Route Type: nextjs
```

Routes will automatically use HTTPS if SSL certificates are installed.

## 📁 Project Structure

```
├── .github/workflows/
│   ├── infrastructure.yml    # Main infrastructure deployment
│   ├── deploy.yml           # Application deployment
│   ├── manage-routes.yml    # Dynamic nginx route management
│   └── setup-https.yml      # SSL certificate installation & management
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
- **HTTPS Support** - Automatic SSL/TLS with Let's Encrypt
- **HTTP to HTTPS Redirect** - Automatic when SSL is configured
- **Security Headers** - HSTS, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection
- **Modern TLS** - TLS 1.2 and 1.3 with secure ciphers
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

## 🔐 HTTPS/SSL Management

### Setup SSL Certificate (First Time)

Use the **Setup HTTPS/SSL** workflow:

| Action | Description | Required Fields |
|--------|-------------|----------------|
| `install` | Install SSL certificate | domain, email |
| `renew` | Manually renew certificate | domain |
| `status` | Check certificate status | domain |

**Example:**
```bash
Domain: test.dev-maestra.vottia.me
Email: admin@example.com
Action: install
```

### Automatic Features
- ✅ **Auto-renewal**: Certificates renew 30 days before expiry
- ✅ **HTTPS redirect**: All HTTP traffic redirects to HTTPS
- ✅ **Security headers**: HSTS enforces HTTPS for 1 year
- ✅ **Fallback**: Works in HTTP-only mode if SSL not configured

## 🌐 Dynamic Route Management

### Available Route Types

#### Normal Apps (Prefix Stripped)
Route requests to apps that don't expect a prefix:
```json
{
  "name": "api-service",
  "path": "/api",
  "type": "proxy",
  "route_type": "normal",
  "target_port": 3001
}
```
Nginx strips `/api` before forwarding to the app.

#### Next.js Apps (Prefix Preserved)
For Next.js apps with `basePath`:
```json
{
  "name": "dashboard",
  "path": "/dashboard",
  "type": "proxy",
  "route_type": "nextjs",
  "target_port": 3000
}
```
Nginx preserves `/dashboard` path for Next.js basePath support.

#### Root Domain
Leave path empty for root domain:
```json
{
  "name": "default",
  "path": "",
  "type": "proxy",
  "route_type": "nextjs",
  "target_port": 3500
}
```

### Route Operations

| Operation | Description | Required Fields |
|-----------|-------------|----------------|
| `list` | Show current routes | None |
| `add` | Create new route | route_name, route_path, target_port, route_type |
| `edit` | Modify route | route_name, route_path, target_port, route_type |
| `delete` | Delete route | route_name |

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

- **HTTPS/TLS Encryption** - Free SSL certificates from Let's Encrypt
- **HSTS Header** - Enforces HTTPS for 1 year
- **Modern TLS** - TLS 1.2 and 1.3 with secure cipher suites
- **SSH Key Authentication** - No password access
- **Firewall Configuration** - Only required ports open
- **Private Registry** - SSH tunnel access only
- **Security Headers** - X-Frame-Options, X-Content-Type-Options, X-XSS-Protection
- **Configuration Backups** - Automatic backup before changes
- **Git Tracking** - All configuration changes versioned
- **Auto SSL Renewal** - Certificates auto-renew before expiry

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