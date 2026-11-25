data "aws_subnet" "isolated" {
  id = var.isolated_subnet_id
}

data "aws_vpc_endpoint_service" "interface" {
  for_each     = toset(["ecr.api", "ecr.dkr", "logs"])
  service      = each.key
  service_type = "Interface"
}

data "aws_vpc_endpoint_service" "s3" {
  service      = "s3"
  service_type = "Gateway"
}

resource "aws_security_group" "application" {
  name_prefix = "${var.name_prefix}-application-"
  description = "Private HTTP from development and HTTPS to image and log endpoints only."
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-application" }
}

resource "aws_vpc_security_group_ingress_rule" "application" {
  security_group_id            = aws_security_group.application.id
  description                  = "Allow development node HTTP requests."
  referenced_security_group_id = var.development_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.application_port
  to_port                      = local.application_port
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${var.name_prefix}-application-endpoints-"
  description = "Image and log endpoints accessible only from application tasks."
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-application-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "Allow task initiated HTTPS to private endpoints"
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "endpoints" {
  security_group_id            = aws_security_group.application.id
  description                  = "Allow HTTPS only to image and log endpoint interfaces"
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "s3" {
  security_group_id = aws_security_group.application.id
  description      = "Allow HTTPS to the regional S3 prefix list for ecr image layers"
  prefix_list_id   = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol      = "tcp"
  from_port        = 443
  to_port          = 443
}

locals {
  # GetAuthorizationToken cannot be scoped to an ECR repository ARN
  ecr_endpoint_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "ecr:GetAuthorizationToken"
        Resource  = "*"
        Condition = { ArnEquals = { "aws:PrincipalArn" = aws_iam_role.execution.arn } }
      },
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource  = var.repository_arn
        Condition = { ArnEquals = { "aws:PrincipalArn" = aws_iam_role.execution.arn } }
      }
    ]
  })

  logs_endpoint_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.application.arn}:log-stream:*"
      Condition = { ArnEquals = { "aws:PrincipalArn" = aws_iam_role.execution.arn } }
    }]
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = data.aws_vpc_endpoint_service.interface
  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [var.isolated_subnet_id]
  security_group_ids  = [aws_security_group.endpoints.id]
  policy              = each.key == "logs" ? local.logs_endpoint_policy : local.ecr_endpoint_policy

  lifecycle {
    precondition {
      condition     = contains(each.value.availability_zones, data.aws_subnet.isolated.availability_zone)
      error_message = "The isolated subnet must support all image and log interface endpoints"
    }
    precondition {
      condition     = data.aws_subnet.isolated.vpc_id == var.vpc_id
      error_message = "The isolated subnet must belong to the application VPC"
    }
  }

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = data.aws_vpc_endpoint_service.s3.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.isolated_route_table_id]

  # ECR signs layer download URL with its own identity not the task role
  # Limit object access to ECR regional layer
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:${data.aws_partition.current.partition}:s3:::prod-${data.aws_region.current.region}-starport-layer-bucket/*"
    }]
  })

  tags = { Name = "${var.name_prefix}-application-s3" }
}
