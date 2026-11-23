variable "name_prefix" {
  description = "Prefix for development resource names."
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC with DNS support and hostnames enabled."
  type        = string
}

variable "subnet_id" {
  description = "Outbound-enabled subnet, including its ready NAT route."
  type        = string
}

variable "instance_type" {
  description = "x86_64 Nitro instance type for the terminal development environment."
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "Optional pinned standard Amazon Linux 2023 x86_64 AMI; null selects the current AWS public parameter."
  type        = string
  default     = null
}

variable "home_volume_size" {
  description = "Persistent developer home volume size in GiB. Increase only; EBS cannot shrink."
  type        = number
  default     = 30

  validation {
    condition     = var.home_volume_size >= 10 && var.home_volume_size == floor(var.home_volume_size)
    error_message = "Use a whole number of at least 10 GiB."
  }
}

variable "terraform_version" {
  description = "Exact stable Terraform CLI version downloaded from releases.hashicorp.com."
  type        = string
  default     = "1.17.2"

  validation {
    condition     = can(regex("^1\\.(1[0-9]|[2-9][0-9])\\.[0-9]+$", var.terraform_version))
    error_message = "Use a stable Terraform 1.x release, version 1.10.0 or newer."
  }
}
