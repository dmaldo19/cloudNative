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

output "development" {
  description = "Development resources and custom session document. check bootstrap separately"
  value = {
    instance_id           = module.development.instance_id
    private_ip            = module.development.private_ip
    ami_id                = module.development.ami_id
    home_volume_id        = module.development.home_volume_id
    security_group_id     = module.development.security_group_id
    endpoint_ids          = module.development.endpoint_ids
    session_document_name = module.development.session_document_name
  }
}

output "development_human_session_policy" {
  description = "Human Session Manager policy"
  value       = module.development.human_session_policy
}
