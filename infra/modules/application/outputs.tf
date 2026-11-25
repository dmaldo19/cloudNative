output "details" {
  description = "Deployment identifiers -> verify private DNS and HTTP from the development node separately"
  value = {
    cluster_name               = aws_ecs_cluster.application.name
    service_name               = aws_ecs_service.application.name
    task_definition_arn        = aws_ecs_task_definition.application.arn
    execution_role_name        = aws_iam_role.execution.name
    task_role_name             = aws_iam_role.task.name
    dns_name                   = "${aws_service_discovery_service.application.name}.${aws_service_discovery_private_dns_namespace.application.name}"
    url                        = "http://${aws_service_discovery_service.application.name}.${aws_service_discovery_private_dns_namespace.application.name}:${local.application_port}/"
    port                       = local.application_port
    security_group_id          = aws_security_group.application.id
    endpoint_security_group_id = aws_security_group.endpoints.id
    isolated_route_table_id    = var.isolated_route_table_id
    cloud_map_service_id       = aws_service_discovery_service.application.id
    log_group_name             = aws_cloudwatch_log_group.application.name
    interface_endpoint_ids     = { for service, endpoint in aws_vpc_endpoint.interface : service => endpoint.id }
    s3_endpoint_id             = aws_vpc_endpoint.s3.id
  }
}
