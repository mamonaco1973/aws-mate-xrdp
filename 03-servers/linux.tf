# ================================================================================
# FILE: linux.tf
# ================================================================================
#
# Purpose:
#   Select the most recent locally-built MATE desktop AMI and launch an
#   EC2 instance based on it. The instance is configured to:
#     - Join an Active Directory domain (via userdata bootstrap)
#     - Mount an Amazon EFS file system for shared storage
#     - Use IAM instance profile for Secrets Manager / SSM access
#
# Design:
#   - AMI resolved dynamically using aws_ami data source filtered by
#     name prefix ("mate_ami*") and owner ("self").
#   - EC2 instance launches in designated subnet with SSH/RDP access
#     controlled by security groups.
#   - Userdata rendered via templatefile() and parameterized at apply.
#
# Notes:
#   - Ensure Packer builds AMIs with the expected name prefix.
#   - Ensure subnet routing and SG rules allow required egress.
#
# ================================================================================


# ================================================================================
# SECTION: AMI Lookup (Latest MATE Desktop AMI)
# ================================================================================

# Retrieve most recent locally-owned AMI matching name prefix.
data "aws_ami" "latest_desktop_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["mate_ami*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  owners = ["self"]
}


# ================================================================================
# SECTION: EC2 Instance (MATE Desktop)
# ================================================================================

# Launch Ubuntu 24.04 desktop instance integrated with AD and EFS.
resource "aws_instance" "mate_instance" {

  # AMI dynamically resolved from data source above.
  ami = data.aws_ami.latest_desktop_ami.id

  # Instance size selected for desktop workload performance.
  instance_type = "m6i.xlarge"

  # Root disk override (gp3 SSD, 64 GiB).
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 64
    delete_on_termination = true
  }

  # Networking configuration.
  subnet_id = data.aws_subnet.vm_subnet_1.id

  vpc_security_group_ids = [
    aws_security_group.ad_ssh_sg.id,
    aws_security_group.ad_rdp_sg.id
  ]

  associate_public_ip_address = true

  # Attach IAM instance profile for Secrets Manager / SSM access.
  iam_instance_profile = aws_iam_instance_profile.ec2_secrets_profile.name

  # Bootstrap script rendered with environment-specific values.
  user_data = templatefile("./scripts/userdata.sh", {
    admin_secret   = "admin_ad_credentials_mate"
    domain_fqdn    = var.dns_zone
    efs_mnt_server = aws_efs_mount_target.efs_mnt_1.dns_name
    netbios        = var.netbios
    realm          = var.realm
    force_group    = "mcloud-users"
  })

  # Standard resource tagging.
  tags = {
    Name = "mate-instance"
  }

  # Ensure EFS and mount targets exist before launch.
  depends_on = [
    aws_efs_file_system.efs,
    aws_efs_mount_target.efs_mnt_1,
    aws_efs_mount_target.efs_mnt_2
  ]
}
