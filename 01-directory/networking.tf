# ================================================================================
# FILE: networking.tf
# ================================================================================
#
# Purpose:
#   Establish a minimal network baseline for the mini-AD lab.
#
# Design:
#   - One VPC with:
#       * Public "vm" subnet for bastion/utility hosts and NAT placement
#       * Private "ad" subnet for domain controller / AD services
#   - Public subnet egress via Internet Gateway (IGW)
#   - Private subnet egress via NAT Gateway (no inbound internet exposure)
#
# Notes:
#   - CIDRs and AZ IDs are examples. Align to your region and IP plan.
#   - NAT Gateway is required if private subnet instances need package
#     repos / OS updates / external dependencies during bootstrap.
#
# ================================================================================


# ================================================================================
# SECTION: VPC
# ================================================================================

# Create VPC for the lab environment.
resource "aws_vpc" "ad-vpc" {
  cidr_block           = "10.0.0.0/24" # /24 for this lab environment
  enable_dns_support   = true          # Required for VPC DNS resolution
  enable_dns_hostnames = true          # Enable EC2 DNS hostnames

  tags = {
    Name = var.vpc_name
  }
}


# ================================================================================
# SECTION: Internet Gateway
# ================================================================================

# Provide internet egress for resources in public subnets.
resource "aws_internet_gateway" "ad-igw" {
  vpc_id = aws_vpc.ad-vpc.id

  tags = {
    Name = "ad-igw"
  }
}


# ================================================================================
# SECTION: Subnets
# ================================================================================

# Public subnet for bastion/utility hosts and NAT Gateway placement.
resource "aws_subnet" "vm-subnet-1" {
  vpc_id                  = aws_vpc.ad-vpc.id
  cidr_block              = "10.0.0.64/26" # ~62 usable IPs
  map_public_ip_on_launch = true           # Auto-assign public IPv4
  availability_zone_id    = "use1-az6"     # Example AZ (region-specific)

  tags = {
    Name = "vm-subnet-1"
  }
}

# Optional second public subnet (uncomment if you want multi-AZ public).
# resource "aws_subnet" "vm-subnet-2" {
#   vpc_id                  = aws_vpc.ad-vpc.id
#   cidr_block              = "10.0.0.128/26" # ~62 usable IPs
#   map_public_ip_on_launch = true            # Auto-assign public IPv4
#   availability_zone_id    = "use1-az4"      # Example AZ (region-specific)
#
#   tags = {
#     Name = "vm-subnet-2"
#   }
# }

# Private subnet for AD/DC services (no public IP assignment).
resource "aws_subnet" "ad-subnet" {
  vpc_id                  = aws_vpc.ad-vpc.id
  cidr_block              = "10.0.0.0/26" # ~62 usable IPs
  map_public_ip_on_launch = false         # Private-only
  availability_zone_id    = "use1-az4"    # Example AZ (region-specific)

  tags = {
    Name = "ad-subnet"
  }
}


# ================================================================================
# SECTION: NAT Gateway
# ================================================================================

# Allocate an Elastic IP for NAT Gateway to provide consistent egress IP.
resource "aws_eip" "nat_eip" {
  tags = {
    Name = "nat-eip"
  }
}

# NAT Gateway must be placed in a public subnet.
# It provides outbound internet for instances in private subnets.
resource "aws_nat_gateway" "ad_nat" {
  subnet_id     = aws_subnet.vm-subnet-1.id # Public subnet placement
  allocation_id = aws_eip.nat_eip.id        # Attach EIP for static egress

  tags = {
    Name = "ad-nat"
  }
}


# ================================================================================
# SECTION: Route Tables
# ================================================================================

# Public route table: default route to IGW for direct internet access.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ad-vpc.id

  tags = {
    Name = "public-route-table"
  }
}

# Public default route to the Internet Gateway.
resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ad-igw.id
}

# Private route table: default route to NAT for outbound-only access.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.ad-vpc.id

  tags = {
    Name = "private-route-table"
  }
}

# Private default route to NAT Gateway (egress without inbound exposure).
resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ad_nat.id
}


# ================================================================================
# SECTION: Route Table Associations
# ================================================================================

# Associate public subnet with public route table.
resource "aws_route_table_association" "rt_assoc_vm_public" {
  subnet_id      = aws_subnet.vm-subnet-1.id
  route_table_id = aws_route_table.public.id
}

# Optional association for second public subnet.
# resource "aws_route_table_association" "rt_assoc_vm_public_2" {
#   subnet_id      = aws_subnet.vm-subnet-2.id
#   route_table_id = aws_route_table.public.id
# }

# Associate private AD subnet with private route table.
resource "aws_route_table_association" "rt_assoc_ad_private" {
  subnet_id      = aws_subnet.ad-subnet.id
  route_table_id = aws_route_table.private.id
}
