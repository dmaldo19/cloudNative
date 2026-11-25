data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  application_port  = 8080
  container_name    = "web"
  task_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_ecs_cluster" "application" {
  name = "${var.name_prefix}-application"
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/ecs/${var.name_prefix}/application"
  retention_in_days = 7
}

# Fargate uses this role to pull the image and deliver container logs
resource "aws_iam_role" "execution" {
  name_prefix        = "${var.name_prefix}-execution-"
  description        = "Fargate image pull and log delivery permissions"
  assume_role_policy = local.task_trust_policy
}

resource "aws_iam_role_policy" "execution" {
  name = "image-pull-and-logs"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = var.repository_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.application.arn}:log-stream:*"
      }
    ]
  })
}

# Container credentials use this separate role...
resource "aws_iam_role" "task" {
  name_prefix        = "${var.name_prefix}-task-"
  description        = "application task identity with no aws service permissions"
  assume_role_policy = local.task_trust_policy
}

resource "aws_service_discovery_private_dns_namespace" "application" {
  name        = "${var.name_prefix}.internal"
  description = "Private application DNS namespace for this VPC."
  vpc         = var.vpc_id
}

resource "aws_service_discovery_service" "application" {
  name        = "web"
  description = "Private task IP addresses with ECS container health"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.application.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  # Custom health is required for ECS health in a private namespace
  health_check_custom_config {
    # AWS fixes this deprecated provider argument at 1
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "application" {
  family                   = "${var.name_prefix}-application"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = local.container_name
    image     = var.image_uri
    essential = true
    portMappings = [{
      containerPort = local.application_port
      hostPort      = local.application_port
      protocol      = "tcp"
    }]
    # ECS does not automatically use healthcheck embedded in the dockerfile
    healthCheck = {
      command = [
        "CMD", "/busybox", "sh", "-c",
        "response=$(/busybox wget -S -O /dev/null http://127.0.0.1:8080/ 2>&1) && echo \"$response\" | /busybox grep -qE 'HTTP/1\\.[01] 200( |$)'"
      ]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.application.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = local.container_name
        mode                  = "non-blocking"
        max-buffer-size       = "1m"
      }
    }
  }])
}

resource "aws_ecs_service" "application" {
  name                               = "${var.name_prefix}-application"
  cluster                            = aws_ecs_cluster.application.id
  task_definition                    = aws_ecs_task_definition.application.arn
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  wait_for_steady_state              = true
  enable_execute_command             = false

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [var.isolated_subnet_id]
    security_groups  = [aws_security_group.application.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.application.arn
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }

  # The image digest and log group are dependencies of the task definition
  # Network policies and routes must also be ready before the first task starts
  depends_on = [
    aws_iam_role_policy.execution,
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3,
    aws_vpc_security_group_ingress_rule.application,
    aws_vpc_security_group_ingress_rule.endpoints,
    aws_vpc_security_group_egress_rule.endpoints,
    aws_vpc_security_group_egress_rule.s3
  ]
}
