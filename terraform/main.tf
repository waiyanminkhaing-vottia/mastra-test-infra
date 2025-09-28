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
      "# Remove the basic server configuration to avoid conflicts",
      "sudo rm -f /etc/nginx/conf.d/nextjs-apps.conf",
      "# Generate nginx configuration from routes using tee for better reliability",
      "sudo tee /etc/nginx/conf.d/dynamic-routes.conf > /dev/null << 'NGINX_EOF'",
      "server {",
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
      "    # Dashboard route (from nginx-routes.json)",
      "    location /dashboard {",
      "        proxy_pass http://127.0.0.1:3000;",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;",
      "        proxy_set_header X-Forwarded-Proto \\$scheme;",
      "    }",
      "",
      "    # Default location",
      "    location / {",
      "        return 200 \"Mastra Infrastructure - Routes loaded from nginx-routes.json\\\\n\";",
      "        add_header Content-Type text/plain;",
      "    }",
      "}",
      "NGINX_EOF",
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
