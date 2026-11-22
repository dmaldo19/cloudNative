variable "aws_region" {
  description = "AWS region for the application infrastructure."
  type        = string
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
