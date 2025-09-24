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
  value       = "ssh -i ~/.ssh/mastra-key ubuntu@${aws_lightsail_static_ip.mastra_static_ip.ip_address}"
}

output "health_check_command" {
  description = "Command to run health check on the instance"
  value       = "./scripts/check-instance-health.sh ${aws_lightsail_static_ip.mastra_static_ip.ip_address}"
}

output "setup_command" {
  description = "Command to manually setup the instance if needed"
  value       = "./scripts/setup-instance.sh ${aws_lightsail_static_ip.mastra_static_ip.ip_address}"
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
  description = "DNS configuration needed"
  value = {
    domain = var.domain_name
    type   = "A"
    value  = aws_lightsail_static_ip.mastra_static_ip.ip_address
    note   = "Point ${var.domain_name} A record to this IP address"
  }
}

output "docker_ports" {
  description = "Docker container port mapping"
  value = {
    main_app   = "Port 3000 (default route)"
    sanden_app = "Port 3001 (/sanden path)"
  }
}