#!/bin/bash
# ================================================================================
# AD + Server Deployment Orchestration Script
# ================================================================================
#
# Purpose:
#   Automate a three-phase AWS build:
#     1. Deploy an AD domain controller environment (Terraform).
#     2. Build a custom MATE XRDP AMI (Packer).
#     3. Deploy EC2 servers that join the AD domain (Terraform).
#
# Design:
#   - Runs a pre-check to validate local prerequisites before any deploy.
#   - Builds AD first to ensure DNS and domain join prerequisites exist.
#   - Derives Packer VPC/subnet inputs from the deployed AD VPC.
#   - Runs post-build validation after all phases complete.
#
# Requirements:
#   - AWS CLI configured with permissions for EC2, VPC, IAM, and related.
#   - Terraform installed and available in PATH.
#   - Packer installed and available in PATH.
#   - ./check_env.sh present and executable.
#   - ./validate.sh present and executable.
#
# Environment Variables:
#   - AWS_DEFAULT_REGION: AWS region for all operations.
#   - DNS_ZONE:          DNS zone for the AD domain.
#
# Exit Codes:
#   - 0: Success.
#   - 1: Failed pre-check or missing required directories.
#
# ================================================================================

set -euo pipefail

# ================================================================================
# SECTION: Configuration
# ================================================================================

export AWS_DEFAULT_REGION="us-east-1"
DNS_ZONE="mcloud.mikecloud.com"

# ================================================================================
# SECTION: Environment Pre-Check
# ================================================================================

# Validate AWS CLI, Terraform, env vars, and local prerequisites.
echo "NOTE: Running environment validation..."
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi

# ================================================================================
# SECTION: Phase 1 - Deploy Active Directory
# ================================================================================

# Deploy AD first so domain join and DNS resolution succeed later.
echo "NOTE: Building Active Directory instance..."

cd 01-directory || { echo "ERROR: Missing 01-directory dir"; exit 1; }

terraform init
terraform apply -auto-approve

cd .. || exit

# ================================================================================
# SECTION: Phase 2 - Build MATE XRDP AMI (Packer)
# ================================================================================

# Build the custom AMI used by the server module.
# Pull VPC and subnet dynamically from the AD VPC to ensure compatibility.

# Resolve VPC ID from tag: Name=mate-vpc.
vpc_id=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=mate-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

# Resolve vm-subnet-1 subnet ID within the mate-vpc VPC.
subnet_id=$(aws ec2 describe-subnets \
  --filters \
    "Name=vpc-id,Values=${vpc_id}" \
    "Name=tag:Name,Values=vm-subnet-1" \
  --query "Subnets[0].SubnetId" \
  --output text)

cd 02-packer || { echo "ERROR: Missing 02-packer dir"; exit 1; }

echo "NOTE: Building MATE XRDP AMI with Packer..."

packer init ./mate_ami.pkr.hcl
packer build -var "vpc_id=${vpc_id}" -var "subnet_id=${subnet_id}" \
  ./mate_ami.pkr.hcl || {
    echo "ERROR: Packer build failed. Aborting."
    cd ..
    exit 1
  }

cd .. || exit

# ================================================================================
# SECTION: Phase 3 - Deploy EC2 Server Instances
# ================================================================================

# Deploy EC2 instances that depend on the AD domain and the custom AMI.
echo "NOTE: Building EC2 server instances..."

cd 03-servers || { echo "ERROR: Missing 03-servers dir"; exit 1; }

terraform init
terraform apply -auto-approve

cd .. || exit

# ================================================================================
# SECTION: Build Validation
# ================================================================================

./validate.sh

