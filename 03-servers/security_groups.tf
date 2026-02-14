# ================================================================================
# FILE: security_groups.tf
# ================================================================================
#
# Purpose:
#   Define baseline security groups for lab access to Windows and Linux
#   instances in the mini-AD VPC.
#
# Design:
#   - ad_rdp_sg:
#       * Inbound RDP (TCP/3389) for Windows remote desktop access.
#       * Inbound ICMP for basic reachability testing.
#   - ad_ssh_sg:
#       * Inbound SSH (TCP/22) for Linux administration.
#       * Inbound SMB (TCP/445) for Samba/SMB testing.
#       * Inbound ICMP for basic reachability testing.
#   - Both SGs allow all outbound traffic.
#
# Security Notes:
#   - Ingress rules are intentionally open (0.0.0.0/0) for lab/demo use.
#   - DO NOT use these rules in production. Restrict inbound access to:
#       * Your public IP (preferred for single admin)
#       * A corporate VPN CIDR
#       * A bastion SG / SSM-only access model
#
# ================================================================================


# ================================================================================
# SECTION: Security Group - RDP + ICMP (Windows Access)
# ================================================================================

# Allow RDP and ICMP to Windows hosts (demo-only open ingress).
resource "aws_security_group" "ad_rdp_sg" {
  name        = "ad-rdp-security-group"
  description = "Allow RDP access from the internet"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # Allow RDP (TCP/3389) from anywhere (demo-only).
  ingress {
    description = "Allow RDP from anywhere"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow ICMP (ping) from anywhere (demo-only).
  ingress {
    description = "Allow ICMP (ping) from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ================================================================================
# SECTION: Security Group - SSH + SMB + ICMP (Linux Access)
# ================================================================================

# Allow SSH, SMB, and ICMP to Linux hosts (demo-only open ingress).
resource "aws_security_group" "ad_ssh_sg" {
  name        = "ad-ssh-security-group"
  description = "Allow SSH access from the internet"
  vpc_id      = data.aws_vpc.ad_vpc.id

  # Allow SSH (TCP/22) from anywhere (demo-only).
  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SMB (TCP/445) from anywhere (demo-only).
  ingress {
    description = "Allow SMB from anywhere"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow ICMP (ping) from anywhere (demo-only).
  ingress {
    description = "Allow ICMP (ping) from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
