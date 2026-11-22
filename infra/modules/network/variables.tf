variable "name_prefix" {
  description = "Prefix for network resource names"
  type        = string
}

variable "availability_zone" {
  description = "Single availability zone for all three subnets"
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 VPC CIDR containing three equal-size subnets"
  type        = string

  validation {
    condition = can(cidrnetmask(var.vpc_cidr)) && try(
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 26,
      false
    )
    error_message = "Use an IPv4 VPC CIDR from /16 to /26 so it can contain at least three AWS subnets"
  }
}

variable "subnet_newbits" {
  description = "Bits added to the VPC prefix and subnet numbers 0 1 and 2 are reserved for public outbound and isolated"
  type        = number

  validation {
    condition = (
      var.subnet_newbits >= 2 &&
      var.subnet_newbits == floor(var.subnet_newbits) &&
      try(tonumber(split("/", var.vpc_cidr)[1]) + var.subnet_newbits <= 28, false)
    )
    error_message = "Use a whole number of at least 2 that leaves subnet prefixes no longer than /28"
  }
}
