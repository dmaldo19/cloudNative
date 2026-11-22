output "vpc_id" {
  description = "VPC ID for workload security groups and private service integrations"
  value       = module.network.vpc_id
}

output "outbound_subnet_id" {
  description = "Subnet ID for the development environment with outbound internet access"
  value       = module.network.outbound_subnet_id
}

output "isolated_subnet_id" {
  description = "Subnet ID for the application with no internet route at all"
  value       = module.network.isolated_subnet_id
}
