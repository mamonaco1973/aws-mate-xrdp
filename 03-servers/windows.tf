# ================================================================================
# FILE: windows.tf
# ================================================================================
#
# Purpose:
#   Provision a Windows Server EC2 instance used as an Active Directory
#   administrative workstation ("jump box") for RDP access and AD tools.
#
# Design:
#   - Intended use:
#       * RDP login for administrators
#       * RSAT / ADUC / PowerShell AD management tooling
#       * Managing AD services running on separate infrastructure
#   - Uses IAM instance profile for secure AWS access (Secrets Manager, SSM).
#   - Bootstraps via PowerShell userdata to:
#       * Retrieve AD admin credentials from Secrets Manager
#       * Join / configure against the AD domain
#       * Reference the Linux Samba/EFS client host for integration tasks
#
# Security Notes:
#   - associate_public_ip_address = true enables direct internet RDP.
#   - Restrict RDP ingress to trusted CIDRs (VPN / admin IP) in production.
#   - Prefer SSM Session Manager over inbound RDP where possible.
#
# ================================================================================


# ================================================================================
# SECTION: EC2 Instance (Windows AD Administration Host)
# ================================================================================

# Windows administrative host for AD management (not a domain controller).
resource "aws_instance" "windows_ad_instance" {

  # Dynamically resolved Windows Server AMI.
  ami = data.aws_ami.windows_ami.id

  # Instance size suitable for RDP sessions and admin tooling.
  instance_type = "t3.medium"

  # Place instance in public/utility subnet.
  subnet_id = data.aws_subnet.vm_subnet_1.id

  # Apply security group permitting inbound RDP (demo-only if open to world).
  vpc_security_group_ids = [
    aws_security_group.ad_rdp_sg.id
  ]

  # Assign public IPv4 for direct RDP connectivity (restrict ingress as needed).
  associate_public_ip_address = true

  # Attach IAM instance profile for Secrets Manager / SSM access.
  iam_instance_profile = aws_iam_instance_profile.ec2_secrets_profile.name

  # Bootstrap instance via PowerShell userdata.
  user_data = templatefile("./scripts/userdata.ps1", {
    admin_secret = "admin_ad_credentials_mate"
    domain_fqdn  = var.dns_zone
    samba_server = aws_instance.mate_instance.private_dns
  })

  # Standard tagging for identification and automation.
  tags = {
    Name = "mate-ad-admin"
  }

  # Ensure Linux Samba/EFS client exists before admin host configuration.
  depends_on = [
    aws_instance.mate_instance
  ]
}
