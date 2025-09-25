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

output "health_check_url" {
  description = "Health check URL for the application"
  value       = "http://${var.domain_name}/health"
}

output "app_urls" {
  description = "Application URLs"
  value = {
    main_app_ip     = "http://${aws_lightsail_static_ip.mastra_static_ip.ip_address}"
    sanden_app_ip   = "http://${aws_lightsail_static_ip.mastra_static_ip.ip_address}/sanden"
    main_app_domain = "http://${var.domain_name}"
    sanden_app_domain = "http://${var.domain_name}/sanden"
    health_check    = "http://${var.domain_name}/health"
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

output "docker_ports" {
  description = "Docker container port mapping"
  value = {
    main_app   = "Port 3000 (default route)"
    sanden_app = "Port 3001 (/sanden path)"
  }
}