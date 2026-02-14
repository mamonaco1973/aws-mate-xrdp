# ================================================================================
# FILE: efs.tf
# ================================================================================
#
# Purpose:
#   Provision an Amazon EFS file system and associated networking
#   components for shared NFS storage within the mini-AD VPC.
#
# Design:
#   - Dedicated security group for NFS (TCP/2049).
#   - Encrypted EFS file system with idempotent creation token.
#   - Mount targets created in specific subnets for EC2 access.
#
# Security Notes:
#   - Ingress rule currently allows 0.0.0.0/0 for lab/demo simplicity.
#   - Production environments should restrict ingress to trusted
#     security groups or specific VPC CIDR ranges only.
#
# ================================================================================


# ================================================================================
# SECTION: Security Group (EFS NFS Access)
# ================================================================================

# Security group dedicated to the EFS file system.
# Allows inbound NFS (TCP/2049) so EC2 instances can mount EFS.
resource "aws_security_group" "efs_sg" {
  name        = "mate-efs-sg"
  description = "Security group allowing NFS traffic to EFS"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # Demo-only ingress rule. Restrict in production.
  ingress {
    description = "Allow inbound NFS traffic"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mate-efs-sg"
  }
}


# ================================================================================
# SECTION: EFS File System
# ================================================================================

# Create encrypted Amazon EFS file system.
# creation_token ensures idempotency across applies.
resource "aws_efs_file_system" "efs" {
  creation_token = "mate-efs"
  encrypted      = true

  tags = {
    Name = "mate-efs"
  }
}


# ================================================================================
# SECTION: EFS Mount Targets
# ================================================================================

# Mount target in VM subnet (public or utility zone).
# One mount target per Availability Zone is recommended.
resource "aws_efs_mount_target" "efs_mnt_1" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = data.aws_subnet.vm_subnet_1.id
  security_groups = [aws_security_group.efs_sg.id]
}

# Mount target in AD subnet (private zone).
# Enables private instances to access the same EFS file system.
resource "aws_efs_mount_target" "efs_mnt_2" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = data.aws_subnet.ad_subnet.id
  security_groups = [aws_security_group.efs_sg.id]
}
