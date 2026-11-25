locals {
  # Fargate must use operating_system_family = "LINUX" and cpu_architecture = "X86_64".
  platform = "linux/amd64"

  # Include relative paths to detect some context
  context_hash = sha256(jsonencode({
    platform = local.platform
    files    = {
      for file in sort(fileset(var.build_context, "**")) :
      file => filesha256("${var.build_context}/${file}")
    }
  }))
}

resource "aws_ecr_repository" "application" {
  name = "${var.name_prefix}-application"

  # rebuilds on another daemon can replace a tag
  image_tag_mutability = "MUTABLE"

  # so it deletes all retained versions when the repository is destroyed.
  force_delete = true

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "docker_image" "application" {
  name         = "${aws_ecr_repository.application.repository_url}:${local.context_hash}"
  platform     = local.platform
  keep_locally = false

  build {
    context     = var.build_context
    platform    = local.platform
    pull_parent = true
  }

  triggers = {
    context_hash = local.context_hash
  }
}

resource "docker_registry_image" "application" {
  name = docker_image.application.name

  # retain previous digests for running tasks 
  # The ECR repository owns final cleanup through force_delete
  keep_remotely = true

  triggers = {
    image_id = docker_image.application.image_id
  }
}
