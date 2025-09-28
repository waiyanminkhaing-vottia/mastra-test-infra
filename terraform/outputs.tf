output "instance_public_ip" {
  description = "Public IP address of the Lightsail instance"
  value       = aws_lightsail_static_ip.mastra_static_ip.ip_address
}

output "instance_private_ip" {
  description = "Private IP address of the Lightsail instance"
  value       = aws_lightsail_instance.mastra_instance.private_ip_address
}

output "instance_name" {
  description = "Name of the Lightsail instance"
  value       = aws_lightsail_instance.mastra_instance.name
}

output "static_ip_name" {
  description = "Name of the static IP"
  value       = aws_lightsail_static_ip.mastra_static_ip.name
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/mastra-key ec2-user@${aws_lightsail_static_ip.mastra_static_ip.ip_address}"
}

output "ssh_private_key" {
  description = "SSH private key for instance access"
  value       = tls_private_key.ssh_key.private_key_pem
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key for instance access"
  value       = tls_private_key.ssh_key.public_key_openssh
}

output "base_urls" {
  description = "Base URLs for dynamic route management"
  value = {
    domain_base = "http://${var.domain_name}"
    ip_base     = "http://${aws_lightsail_static_ip.mastra_static_ip.ip_address}"
    note        = "Routes are managed dynamically via GitHub Actions workflow"
  }
}

output "dns_configuration" {
  description = "DNS configuration"
  value = {
    domain            = var.domain_name
    type              = "A"
    ip_address        = aws_lightsail_static_ip.mastra_static_ip.ip_address
    auto_created      = "DNS A record created automatically in Route53"
  }
}

output "route53_info" {
  description = "Route53 hosted zone information"
  value = {
    hosted_zone_id = data.aws_route53_zone.existing_zone.zone_id
    domain         = data.aws_route53_zone.existing_zone.name
    name_servers   = data.aws_route53_zone.existing_zone.name_servers
    setup_note     = "Using existing hosted zone - nameservers should already be configured"
  }
}

output "infrastructure_info" {
  description = "Infrastructure management information"
  value = {
    route_management   = "Use GitHub Actions 'Manage Nginx Routes' workflow to add/remove routes"
    docker_registry    = "Private registry available via SSH tunnel on port 5000"
    available_ports    = "3000-3010 (configure routes to point to your application ports)"
    registry_access    = "ssh -L 5000:localhost:5000 ec2-user@${aws_lightsail_static_ip.mastra_static_ip.ip_address}"
  }
}