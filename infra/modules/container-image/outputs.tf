output "image_uri" {
  description = "Immutable image reference and available only after publication completes"
  value       = "${aws_ecr_repository.application.repository_url}@${docker_registry_image.application.sha256_digest}"
}

output "repository_name" {
  description = "Private ECR repository name."
  value       = aws_ecr_repository.application.name
}
