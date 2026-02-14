# ================================================================================
# FILE: mate.pkr.hcl
# ================================================================================
#
# Purpose:
#   Build a custom Ubuntu 24.04 (Noble) AMI with the MATE desktop and XRDP
#   enabled, plus common admin and development tooling.
#
# Design:
#   - Base image: latest Canonical Ubuntu 24.04 AMI (Noble).
#   - Builder: amazon-ebs (launch temp EC2, provision, create AMI).
#   - Output: timestamped AMI name and tags for repeatable builds.
#   - Provisioning: ordered shell scripts, executed with sudo.
#
# Notes:
#   - subnet_id must allow outbound internet access for package installs.
#   - Uses public_ip SSH during build for simplicity.
#
# ================================================================================


# ================================================================================
# SECTION: Packer Plugin Configuration
# ================================================================================

# Define required plugins for interacting with AWS.
packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}


# ================================================================================
# SECTION: Base Ubuntu 24.04 AMI Lookup
# ================================================================================

# Fetch the most recent Canonical Ubuntu 24.04 (Noble) AMI.
# - Filters to HVM virtualization and EBS-backed storage.
data "amazon-ami" "ubuntu_2404" {
  filters = {
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    virtualization-type = "hvm"
    root-device-type    = "ebs"
  }

  most_recent = true
  owners      = ["099720109477"]
}


# ================================================================================
# SECTION: Build-Time Variables
# ================================================================================

# Target AWS region for AMI build.
variable "region" {
  default = "us-east-1"
}

# Instance type for the temporary builder host.
# Using a larger instance can reduce build time for desktop/tool installs.
variable "instance_type" {
  default = "m5.2xlarge"
}

# VPC ID used for the temporary builder host.
# Typically supplied by pipeline or environment wrapper.
variable "vpc_id" {
  description = "The ID of the VPC to use"
  default     = ""
}

# Subnet ID used for the temporary builder host.
# Must permit outbound internet access for apt and downloads.
variable "subnet_id" {
  description = "The ID of the subnet to use"
  default     = ""
}


# ================================================================================
# SECTION: Amazon-EBS Builder Source
# ================================================================================

# Launch a temporary EC2 instance, provision it, and capture an AMI.
source "amazon-ebs" "mate_ami" {
  region        = var.region
  instance_type = var.instance_type
  source_ami    = data.amazon-ami.ubuntu_2404.id
  ssh_username  = "ubuntu"
  ssh_interface = "public_ip"
  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id

  # Name and tag AMI with a timestamp for uniqueness.
  ami_name = format(
    "mate_ami_%s",
    replace(timestamp(), ":", "-")
  )

  # Configure root volume for desktop workload and tooling footprint.
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 64
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = format(
      "mate_ami_%s",
      replace(timestamp(), ":", "-")
    )
  }
}


# ================================================================================
# SECTION: Build Provisioners
# ================================================================================

# Execute provisioning scripts inside the temporary builder instance.
# Each script is run with sudo and inherits environment variables (-E).
build {
  sources = ["source.amazon-ebs.mate_ami"]

  # Install base packages and dependencies.
  provisioner "shell" {
    script          = "./packages.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install MATE desktop environment.
  provisioner "shell" {
    script          = "./mate.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install XRDP for remote desktop access.
  provisioner "shell" {
    script          = "./xrdp.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Google Chrome browser.
  provisioner "shell" {
    script          = "./chrome.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Firefox browser.
  provisioner "shell" {
    script          = "./firefox.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Visual Studio Code.
  provisioner "shell" {
    script          = "./vscode.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install HashiCorp tooling (terraform, packer, etc.).
  provisioner "shell" {
    script          = "./hashicorp.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install AWS CLI.
  provisioner "shell" {
    script          = "./awscli.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Azure CLI.
  provisioner "shell" {
    script          = "./azcli.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Google Cloud CLI (gcloud).
  provisioner "shell" {
    script          = "./gcloudcli.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Docker engine and tooling.
  provisioner "shell" {
    script          = "./docker.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install Postman client.
  provisioner "shell" {
    script          = "./postman.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install OnlyOffice desktop suite.
  provisioner "shell" {
    script          = "./onlyoffice.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Install KRDC (RDP client).
  provisioner "shell" {
    script          = "./krdc.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  # Configure desktop shortcuts / icons.
  provisioner "shell" {
    script          = "./desktop.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
  }
}
