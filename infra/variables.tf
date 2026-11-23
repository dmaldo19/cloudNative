variable "aws_region" {
  description = "AWS region for the application infrastructure."
  type        = string
}

variable "aws_account_id" {
  description = "Expected target account ID. Use separate backend configuration and input files for each account"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide the expected AWS account ID"
  }
}

variable "project_name" {
  description = "Project name used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
}

variable "availability_zone" {
  description = "Single availability zone for all subnets, within aws_region"
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 VPC CIDR from /16 to /26, containing the three workload and NAT subnets"
  type        = string
}

variable "subnet_newbits" {
  description = "Bits added to the VPC prefix for three equal-size subnets -> 8 turns a /16 into /24 subnets"
  type        = number
  default     = 8
}

variable "development_instance_type" {
  description = "x86_64 Nitro instance type; t3.medium provides 2 vCPUs and 4 GiB RAM."
  type        = string
  default     = "t3.medium"
}

variable "development_ami_id" {
  description = "Optional region-specific standard AL2023 x86_64 AMI ID. Null uses AWS's current public parameter."
  type        = string
  default     = null
}

variable "development_home_volume_size" {
  description = "Separate encrypted developer home volume size in GiB."
  type        = number
  default     = 30
}

variable "development_terraform_version" {
  description = "Exact Terraform CLI release installed automatically on the development node."
  type        = string
  default     = "1.17.2"
}
