locals {
  vpc_az_a                              = "${var.region}a"
  vpc_cidr                              = "10.0.0.0/16"
  vpc_public_az_a_subnet_cidr           = "10.0.0.0/24"
  vpc_public_az_a_subnet_app_ip_address = "10.0.0.4"
  vpc_public_az_a_subnet_ipv6_cidr      = cidrsubnet(aws_vpc.example.ipv6_cidr_block, 8, 0) # NB this must be a /64 subnet. ipv6_cidr_block is a /56 subnet.
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.example.id
  tags = {
    Name = var.name_prefix
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
resource "aws_vpc" "example" {
  cidr_block                       = local.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  tags = {
    Name = var.name_prefix
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "public_az_a" {
  vpc_id                          = aws_vpc.example.id
  availability_zone               = local.vpc_az_a
  cidr_block                      = local.vpc_public_az_a_subnet_cidr
  ipv6_cidr_block                 = local.vpc_public_az_a_subnet_ipv6_cidr
  assign_ipv6_address_on_creation = true
  tags = {
    Name = "${var.name_prefix}-public-az-a"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }
  tags = {
    Name = "${var.name_prefix}-public"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "public_az_a" {
  subnet_id      = aws_subnet.public_az_a.id
  route_table_id = aws_route_table.public.id
}
