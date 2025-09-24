terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}


# Try to get existing SSH key pair first
data "aws_lightsail_key_pair" "existing_key" {
  count = var.use_existing_key_pair ? 1 : 0
  name  = "${var.project_name}-key"
}

# Generate SSH key pair only if not using existing
resource "tls_private_key" "ssh_key" {
  count     = var.use_existing_key_pair ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create a key pair for the instance using generated key (only if not using existing)
resource "aws_lightsail_key_pair" "mastra_key" {
  count      = var.use_existing_key_pair ? 0 : 1
  name       = "${var.project_name}-key"
  public_key = tls_private_key.ssh_key[count.index].public_key_openssh

  lifecycle {
    ignore_changes = [public_key]
  }
}

# Create the Lightsail instance
resource "aws_lightsail_instance" "mastra_instance" {
  name              = "${var.project_name}-instance"
  availability_zone = data.aws_availability_zones.available.names[0]
  blueprint_id      = "amazon_linux_2023"
  bundle_id         = var.instance_bundle_id
  key_pair_name     = var.use_existing_key_pair ? data.aws_lightsail_key_pair.existing_key[0].name : aws_lightsail_key_pair.mastra_key[0].name
  user_data         = file("${path.module}/user_data.sh")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
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
  name = "${var.project_name}-static-ip"

  lifecycle {
    prevent_destroy = true
  }
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

# Create Route53 hosted zone if it doesn't exist
resource "aws_route53_zone" "demo_zone" {
  count = !var.skip_route53 && var.create_hosted_zone ? 1 : 0
  name  = var.base_domain

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Get the hosted zone for the domain (existing or newly created)
data "aws_route53_zone" "domain" {
  count        = !var.skip_route53 && var.create_dns_record && !var.create_hosted_zone ? 1 : 0
  name         = var.base_domain
  private_zone = false
}

# Create A record for the subdomain - using local to determine zone_id
locals {
  zone_id = var.create_hosted_zone && length(aws_route53_zone.demo_zone) > 0 ? aws_route53_zone.demo_zone[0].zone_id : (
    length(data.aws_route53_zone.domain) > 0 ? data.aws_route53_zone.domain[0].zone_id : null
  )
}

resource "aws_route53_record" "subdomain" {
  count           = !var.skip_route53 && var.create_dns_record && local.zone_id != null ? 1 : 0
  zone_id         = local.zone_id
  name            = var.domain_name
  type            = "A"
  ttl             = 300
  records         = [aws_lightsail_static_ip.mastra_static_ip.ip_address]
  allow_overwrite = true

  lifecycle {
    ignore_changes = [records]
  }
}

