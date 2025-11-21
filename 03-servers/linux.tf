data "aws_ami" "latest_desktop_ami" {
  most_recent = true                    # Return the most recently created AMI matching filters

  filter {
    name   = "name"                     # Filter AMIs by name pattern
    values = ["xubuntu_ami*"]           # Match AMI names starting with "xubuntu_ami"
  }

  filter {
    name   = "state"                    # Filter AMIs by state
    values = ["available"]              # Ensure AMI is in 'available' state
  }

  owners = ["self"]                     # Limit to AMIs owned by current AWS account
}

# ================================================================================================
# EC2 Instance: Xubuntu Desktop
# ================================================================================================
# Provisions an Ubuntu 24.04 EC2 instance that mounts an Amazon EFS file system and
# integrates into an Active Directory (AD) environment.
# ================================================================================================
resource "aws_instance" "xubuntu_instance" {

  # ----------------------------------------------------------------------------------------------
  # Amazon Machine Image (AMI)
  # ----------------------------------------------------------------------------------------------
  # Dynamically resolved to the latest Xubuntu AMI built via Packer.
  ami = data.aws_ami.latest_desktop_ami.id

  # ----------------------------------------------------------------------------------------------
  # Instance Type
  # ----------------------------------------------------------------------------------------------
  # Defines the compute and memory capacity of the instance.
  # Selected as "m5.xlarge" for better performance with desktop workloads.

  instance_type = "m5.xlarge"

  # ----------------------------------------------------------------------------------------------
  # Root Block Device
  # ----------------------------------------------------------------------------------------------
  # Override default AMI disk size and storage configuration.
  # - gp3 SSD with 64 GiB capacity
  # - Baseline throughput and IOPS are the gp3 defaults
  root_block_device {
    volume_type = "gp3"
    volume_size = 64
    delete_on_termination = true
  }

  # ----------------------------------------------------------------------------------------------
  # Networking
  # ----------------------------------------------------------------------------------------------
  # - Places the instance into a designated VPC subnet.
  # - Applies one or more security groups to control inbound/outbound traffic.
  subnet_id = data.aws_subnet.vm_subnet_1.id

  vpc_security_group_ids = [
    aws_security_group.ad_ssh_sg.id,
    aws_security_group.ad_rdp_sg.id  # Allows RDP access; extend with SSM SG if required
  ]

  # Assigns a public IP to the instance at launch (enables external SSH/RDP if allowed by SGs).
  associate_public_ip_address = true

  # ----------------------------------------------------------------------------------------------
  # IAM Role / Instance Profile
  # ----------------------------------------------------------------------------------------------
  # Attaches an IAM instance profile that grants the EC2 instance permissions to interact
  # with AWS services (e.g., Secrets Manager for credential retrieval, SSM for management).
  iam_instance_profile = aws_iam_instance_profile.ec2_secrets_profile.name

  # ----------------------------------------------------------------------------------------------
  # User Data (Bootstrapping)
  # ----------------------------------------------------------------------------------------------
  # Executes a startup script on first boot.
  # The script is parameterized with environment-specific values:
  # - admin_secret   : Name of the AWS Secrets Manager secret with AD admin credentials
  # - domain_fqdn    : Fully Qualified Domain Name of the AD domain
  # - efs_mnt_server : DNS name of the EFS mount target
  # - netbios        : NetBIOS short name of the AD domain
  # - realm          : Kerberos realm (usually uppercase domain name)
  # - force_group    : Default group applied to created files/directories
  user_data = templatefile("./scripts/userdata.sh", {
    admin_secret   = "admin_ad_credentials"
    domain_fqdn    = var.dns_zone
    efs_mnt_server = aws_efs_mount_target.efs_mnt_1.dns_name
    netbios        = var.netbios
    realm          = var.realm
    force_group    = "mcloud-users"
  })

  # ----------------------------------------------------------------------------------------------
  # Tags
  # ----------------------------------------------------------------------------------------------
  # Standard AWS tagging for identification, cost tracking, and automation workflows.
  tags = {
    Name = "xubuntu-instance"
  }

  # ----------------------------------------------------------------------------------------------
  # Dependencies
  # ----------------------------------------------------------------------------------------------
  # Ensures the Amazon EFS file system exists before the client instance is launched.
  depends_on = [aws_efs_file_system.efs, aws_efs_mount_target.efs_mnt_1, aws_efs_mount_target.efs_mnt_2]
}
