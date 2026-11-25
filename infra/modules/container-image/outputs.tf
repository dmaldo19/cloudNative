output "image_uri" {
  description = "Immutable image reference and available only after publication completes"
  value       = "${aws_ecr_repository.application.repository_url}@${docker_registry_image.application.sha256_digest}"
}

output "repository_name" {
  description = "Private ECR repository name."
  value       = aws_ecr_repository.application.name
}

output "repository_arn" {
  description = "Repository ARN for scoped task execution and endpoint permissions"
  value       = aws_ecr_repository.application.arn
}
