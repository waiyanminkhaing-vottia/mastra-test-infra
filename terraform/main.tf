terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# Generate SSH key pair for the instance
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create key pair for the instance
resource "aws_lightsail_key_pair" "mastra_key" {
  name       = "${var.environment}-${var.project_name}-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Create the Lightsail instance
resource "aws_lightsail_instance" "mastra_instance" {
  name              = "${var.environment}-${var.project_name}-instance"
  availability_zone = data.aws_availability_zones.available.names[0]
  blueprint_id      = "amazon_linux_2023"
  bundle_id         = var.instance_bundle_id
  key_pair_name     = aws_lightsail_key_pair.mastra_key.name
  user_data         = file("${path.module}/user_data.sh")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Copy nginx routes configuration to the instance
  provisioner "file" {
    source      = "${path.module}/../nginx-routes.json"
    destination = "/tmp/nginx-routes.json"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = self.public_ip_address
      timeout     = "5m"
    }
  }

  # Apply the routes configuration after file transfer
  provisioner "remote-exec" {
    inline = [
      "# Wait for user_data script to complete",
      "while [ ! -f /home/ec2-user/.setup-completed ]; do sleep 10; done",
      "# Create nginx config directory if it doesn't exist",
      "sudo mkdir -p /etc/nginx/routes",
      "# Move routes file to nginx config directory",
      "sudo mv /tmp/nginx-routes.json /etc/nginx/routes/",
      "# Remove conflicting configurations to avoid conflicts",
      "sudo rm -f /etc/nginx/conf.d/nextjs-apps.conf",
      "# Backup original nginx.conf and create minimal version",
      "sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup",
      "sudo tee /etc/nginx/nginx.conf > /dev/null << 'MAIN_NGINX_EOF'",
      "user nginx;",
      "worker_processes auto;",
      "error_log /var/log/nginx/error.log notice;",
      "pid /run/nginx.pid;",
      "events {",
      "    worker_connections 1024;",
      "}",
      "http {",
      "    log_format  main  '\\$remote_addr - \\$remote_user [\\$time_local] \"\\$request\" '",
      "                      '\\$status \\$body_bytes_sent \"\\$http_referer\" '",
      "                      '\"\\$http_user_agent\" \"\\$http_x_forwarded_for\"';",
      "    access_log  /var/log/nginx/access.log  main;",
      "    sendfile            on;",
      "    tcp_nopush          on;",
      "    keepalive_timeout   65;",
      "    types_hash_max_size 4096;",
      "    include             /etc/nginx/mime.types;",
      "    default_type        application/octet-stream;",
      "    include /etc/nginx/conf.d/*.conf;",
      "}",
      "MAIN_NGINX_EOF",
      "# Generate nginx configuration dynamically from routes JSON",
      "python3 << 'PYTHON_EOF'",
      "import json",
      "",
      "# Read routes from JSON file",
      "try:",
      "    with open('/etc/nginx/routes/nginx-routes.json', 'r') as f:",
      "        config = json.load(f)",
      "except:",
      "    config = {'routes': []}",
      "",
      "# Generate nginx server block",
      "nginx_config = '''server {",
      "    listen 80 default_server;",
      "    server_name _;",
      "",
      "    # Security headers",
      "    add_header X-Frame-Options \"SAMEORIGIN\" always;",
      "    add_header X-Content-Type-Options \"nosniff\" always;",
      "    add_header X-XSS-Protection \"1; mode=block\" always;",
      "",
      "    client_max_body_size 10M;",
      "",
      "'''",
      "",
      "# Add routes from JSON",
      "root_route_exists = False",
      "for route in config.get('routes', []):",
      "    if route['type'] == 'proxy':",
      "        path = route['path']",
      "        port = route['target_port']",
      "        route_type = route.get('route_type', 'normal')",
      "",
      "        # Handle root path specially",
      "        if path == '/' or path == '':",
      "            root_route_exists = True",
      "            nginx_config += f'''",
      "    # Route: {route['name']} - root domain ({route_type})",
      "    location / {{",
      "        proxy_pass http://127.0.0.1:{port}/;",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;",
      "        proxy_set_header X-Forwarded-Proto \\$scheme;",
      "    }}",
      "'''",
      "        else:",
      "            if route_type == 'nextjs':",
      "                # Next.js apps with basePath - preserve full path",
      "                nginx_config += f'''",
      "    # Route: {route['name']} - Next.js with basePath",
      "    location {path}/ {{",
      "        proxy_pass http://127.0.0.1:{port}{path}/;",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;",
      "        proxy_set_header X-Forwarded-Proto \\$scheme;",
      "    }}",
      "",
      "    # Handle {path} without trailing slash",
      "    location = {path} {{",
      "        proxy_pass http://127.0.0.1:{port}{path};",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;",
      "        proxy_set_header X-Forwarded-Proto \\$scheme;",
      "    }}",
      "'''",
      "            else:",
      "                # Normal apps - strip prefix",
      "                nginx_config += f'''",
      "    # Route: {route['name']} - normal app (prefix stripped)",
      "    location {path}/ {{",
      "        rewrite ^{path}(/.*)?$ $1 break;",
      "        proxy_pass http://127.0.0.1:{port}/;",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;",
      "        proxy_set_header X-Forwarded-Proto \\$scheme;",
      "    }}",
      "",
      "    # Handle {path} without trailing slash",
      "    location = {path} {{",
      "        rewrite ^{path}$ / break;",
      "        proxy_pass http://127.0.0.1:{port};",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;",
      "        proxy_set_header X-Forwarded-Proto \\$scheme;",
      "    }}",
      "'''",
      "",
      "# Add default location only if no root route exists",
      "if not root_route_exists:",
      "    nginx_config += '''",
      "    # Default location",
      "    location / {",
      "        return 200 \"Mastra Infrastructure - Routes managed via GitHub Actions\\\\n\";",
      "        add_header Content-Type text/plain;",
      "    }",
      "'''",
      "",
      "nginx_config += '''",
      "}",
      "'''",
      "",
      "# Write nginx configuration",
      "with open('/tmp/dynamic-routes.conf', 'w') as f:",
      "    f.write(nginx_config)",
      "PYTHON_EOF",
      "# Move generated config to nginx directory",
      "sudo mv /tmp/dynamic-routes.conf /etc/nginx/conf.d/dynamic-routes.conf",
      "# Test nginx configuration",
      "sudo nginx -t",
      "# Reload nginx if configuration is valid",
      "sudo systemctl reload nginx"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = self.public_ip_address
      timeout     = "5m"
    }
  }
}

# Open necessary ports using correct Lightsail resource
resource "aws_lightsail_instance_public_ports" "mastra_instance_ports" {
  instance_name = aws_lightsail_instance.mastra_instance.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }

  port_info {
    protocol  = "tcp"
    from_port = 5432
    to_port   = 5432
  }
}

# Create static IP
resource "aws_lightsail_static_ip" "mastra_static_ip" {
  name = "${var.environment}-${var.project_name}-static-ip"
}

# Attach static IP to instance
resource "aws_lightsail_static_ip_attachment" "mastra_static_ip_attachment" {
  static_ip_name = aws_lightsail_static_ip.mastra_static_ip.id
  instance_name  = aws_lightsail_instance.mastra_instance.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Use existing Route53 hosted zone
data "aws_route53_zone" "existing_zone" {
  name = var.base_domain
}

# Create A record for the domain in existing hosted zone
resource "aws_route53_record" "domain_record" {
  zone_id = data.aws_route53_zone.existing_zone.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_lightsail_static_ip.mastra_static_ip.ip_address]
}
