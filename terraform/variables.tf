variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "mastra-test"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "instance_bundle_id" {
  description = "Lightsail instance bundle ID (2 vCPU, 4 GB RAM, 80 GB SSD)"
  type        = string
  default     = "medium_2_0"
}


variable "domain_name" {
  description = "Custom domain name for the application"
  type        = string
  default     = "test.dev-maestra.vottia.me"
}

variable "base_domain" {
  description = "Base domain name (Route53 hosted zone)"
  type        = string
  default     = "dev-maestra.vottia.me"
}

variable "create_dns_record" {
  description = "Whether to create DNS A record automatically (requires Route53 hosted zone)"
  type        = bool
  default     = true
}
