terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}


# Create a key pair for the instance
resource "aws_lightsail_key_pair" "mastra_key" {
  name       = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

# Create the Lightsail instance
resource "aws_lightsail_instance" "mastra_instance" {
  name              = "${var.project_name}-instance"
  availability_zone = data.aws_availability_zones.available.names[0]
  blueprint_id      = "ubuntu_22_04"
  bundle_id         = var.instance_bundle_id
  key_pair_name     = aws_lightsail_key_pair.mastra_key.name
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

