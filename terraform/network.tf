# custom VPC with a public subnet in each AZ:
# VPC, IGW, one public /24 subnet per AZ, and a single route table sending 0.0.0.0/0 to the IGW

# dynamically fetch a list of available AZs within the region configured in the provider
data "aws_availability_zones" "available" {
  state = "available"
}

# slice the full list of regional AZs down to the number defined by var.az_count
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# VPC resource
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # enable DNS resolver inside the VPC
  enable_dns_hostnames = true # enable DNS hostnames for ENIs, required for ECS service discovery

  tags = { Name = "${var.name_prefix}-vpc" }
}

# VPC Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-igw" }
}

# Public subnets, one /24 per AZ carved out of the VPC CIDR
resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id = aws_vpc.this.id

  # assigns the current AZ name (like us-east-1a) to the resource being created
  availability_zone = each.key

  # calculate the unique IP range (CIDR block) for each subnet
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value)

  tags = { Name = "${var.name_prefix}-public-${each.key}" }
}

# route table for public subnets, with a default route to the Internet Gateway (IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-public" }
}

# associate the public route table with each public subnet
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
