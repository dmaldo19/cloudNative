output "vpc_id" {
  description = "VPC ID for workload security groups and private service integrations"
  value       = aws_vpc.this.id
}

output "outbound_subnet_id" {
  description = "Subnet ID for workloads with outbound internet access"
  value       = aws_subnet.outbound.id

  # Wait for the outbound path before consumers bootstrap workloads
  depends_on = [aws_route.outbound_internet, aws_route_table_association.outbound]
}

output "isolated_subnet_id" {
  description = "Subnet ID for workloads with no internet route at all"
  value       = aws_subnet.isolated.id

  depends_on = [aws_route_table_association.isolated]
}

output "isolated_route_table_id" {
  description = "Isolated route table for the private S3 gateway endpoint"
  value       = aws_route_table.isolated.id
}
