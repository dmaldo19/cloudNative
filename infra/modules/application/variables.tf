variable "name_prefix" {
  description = "Project and environment prefix for application resources and private DNS"
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC with DNS support and DNS hostnames enabled"
  type        = string
}

variable "isolated_subnet_id" {
  description = "Application subnet with no internet or NAT route"
  type        = string
}

variable "isolated_route_table_id" {
  description = "Route table associated with the isolated subnet, for S3 endpoint routing"
  type        = string
}

variable "development_security_group_id" {
  description = "Only security group allowed to initiate application HTTP connections"
  type        = string
}

variable "image_uri" {
  description = "Linux amd64 ECR image digest reference, available after Terraform publishes it"
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image_uri))
    error_message = "Use a published ECR image reference with an immutable sha256 digest"
  }
}

variable "repository_arn" {
  description = "Private ECR repository ARN allowed for image pulls"
  type        = string
}
