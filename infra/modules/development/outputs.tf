output "instance_id" {
  description = "Development node ID. Running does not imply bootstrap completion."
  value       = aws_instance.development.id
}

output "private_ip" {
  description = "Development node private IPv4 address."
  value       = aws_instance.development.private_ip
}

output "ami_id" {
  description = "Resolved standard AL2023 AMI ID; pin this input for reproducible future plans."
  value       = aws_instance.development.ami
}

output "home_volume_id" {
  description = "Independent encrypted home volume, deleted by terraform destroy."
  value       = aws_ebs_volume.home.id
}

output "security_group_id" {
  description = "Development security group for future private application ingress references."
  value       = aws_security_group.development.id
}

output "endpoint_ids" {
  description = "Private SSM API and message channel endpoint IDs."
  value       = { for service, endpoint in aws_vpc_endpoint.session_manager : service => endpoint.id }
}

output "session_document_name" {
  description = "Custom Session Manager document that opens the persistent developer home."
  value       = aws_ssm_document.developer_session.name
}

output "human_session_policy" {
  description = "Policy to request for the human identity; not attached to any identity by this module."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = aws_instance.development.arn
        Condition = {
          BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:StartSession", "ssm:GetDocument"]
        Resource = aws_ssm_document.developer_session.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession", "ssmmessages:OpenDataChannel"]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${split(":", aws_instance.development.arn)[4]}:session/*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/aws:ssmmessages:session-id" = "$${aws:userid}"
            "ssm:resourceTag/aws:ssmmessages:target-id"  = aws_instance.development.id
          }
        }
      }
    ]
  })
}
