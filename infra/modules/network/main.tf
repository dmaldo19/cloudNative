resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = false

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.this.id
  availability_zone               = var.availability_zone
  cidr_block                      = cidrsubnet(var.vpc_cidr, var.subnet_newbits, 0)
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

resource "aws_subnet" "outbound" {
  vpc_id                          = aws_vpc.this.id
  availability_zone               = var.availability_zone
  cidr_block                      = cidrsubnet(var.vpc_cidr, var.subnet_newbits, 1)
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  tags = {
    Name = "${var.name_prefix}-outbound"
  }
}

resource "aws_subnet" "isolated" {
  vpc_id                          = aws_vpc.this.id
  availability_zone               = var.availability_zone
  cidr_block                      = cidrsubnet(var.vpc_cidr, var.subnet_newbits, 2)
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  tags = {
    Name = "${var.name_prefix}-isolated"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id     = aws_eip.nat.id
  subnet_id         = aws_subnet.public.id
  connectivity_type = "public"

  depends_on = [aws_route.public_internet, aws_route_table_association.public]

  tags = {
    Name = "${var.name_prefix}-nat"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "outbound" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-outbound"
  }
}

resource "aws_route" "outbound_internet" {
  route_table_id         = aws_route_table.outbound.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "outbound" {
  subnet_id      = aws_subnet.outbound.id
  route_table_id = aws_route_table.outbound.id
}

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-isolated"
  }
}

resource "aws_route_table_association" "isolated" {
  subnet_id      = aws_subnet.isolated.id
  route_table_id = aws_route_table.isolated.id
}
