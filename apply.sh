#!/bin/bash
# ================================================================================================
# AD + Server Deployment Orchestration Script
# ================================================================================================
# Description:
#   Automates a two-phase AWS build:
#     1. Deploys an AD Domain Controller.
#     2. Builds a Packer AMI for Xubuntu XRDP.
#     3. Deploys EC2 servers that join the AD domain.
#
# Goal:
#   Produce a fully configured Xubuntu XRDP server joined to the AD domain.
#
# Key Features:
#   - Runs environment checks before starting the build.
#   - Uses Terraform modules for predictable deployments.
#   - Builds a custom Xubuntu XRDP AMI using Packer.
#   - Ensures servers deploy only after AD is available.
#   - Runs validation checks after all phases complete.
#
# Requirements:
#   - AWS CLI installed and configured.
#   - Terraform installed and available in PATH.
#   - check_env.sh for pre-check validation.
#   - validate.sh for post-build verification.
#
# Environment Variables:
#   - AWS_DEFAULT_REGION : AWS region for deployment.
#   - DNS_ZONE           : DNS zone for the AD domain.
#
# Exit Codes:
#   - 0 : Success.
#   - 1 : Failed pre-check or missing dirs.
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"   # Region for all deployed resources
DNS_ZONE="mcloud.mikecloud.com"         # AD DNS zone used by Terraform
set -e                                  # Exit on any non-zero command

# ------------------------------------------------------------------------------------------------
# Environment Pre-Check
# ------------------------------------------------------------------------------------------------
# Validates AWS CLI, Terraform, env vars, and local prerequisites.
# Prevents build attempts when environment is not ready.
# ------------------------------------------------------------------------------------------------
echo "NOTE: Running environment validation..."
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi

# ------------------------------------------------------------------------------------------------
# Phase 1: Build AD Instance
# ------------------------------------------------------------------------------------------------
# Deploys the AD Domain Controller. Servers are deployed only after AD is
# fully available to ensure proper domain join and DNS resolution.
# ------------------------------------------------------------------------------------------------
echo "NOTE: Building Active Directory instance..."

cd 01-directory || { echo "ERROR: Missing 01-directory dir"; exit 1; }

terraform init                          # Init backend and providers
terraform apply -auto-approve           # Build AD module

cd .. || exit

# ------------------------------------------------------------------------------------------------
# Phase 2: Build Xubuntu XRDP AMI with Packer
# ------------------------------------------------------------------------------------------------
# Creates the custom Xubuntu XRDP AMI used by the server module. Networking
# values are pulled dynamically from the AD VPC to ensure compatibility.
# ------------------------------------------------------------------------------------------------

# Extract VPC ID for Packer build
vpc_id=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=ad-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

# Extract subnet for Packer build
subnet_id=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=vm-subnet-1" \
  --query "Subnets[0].SubnetId" \
  --output text)

cd 02-packer || { echo "ERROR: Missing 02-packer dir"; exit 1; }

echo "NOTE: Building Xubuntu XRDP AMI with Packer..."

packer init ./xubuntu_ami.pkr.hcl
packer build -var "vpc_id=$vpc_id" -var "subnet_id=$subnet_id" \
  ./xubuntu_ami.pkr.hcl || {
    echo "ERROR: Packer build failed. Aborting."
    cd ..
    exit 1
  }

cd .. || exit

# ------------------------------------------------------------------------------------------------
# Phase 3: Build EC2 Server Instances
# ------------------------------------------------------------------------------------------------
# Deploys EC2 servers that rely on the AD domain. This includes the Xubuntu
# XRDP instance built from the custom AMI created in Phase 2.
# ------------------------------------------------------------------------------------------------
echo "NOTE: Building EC2 server instances..."

cd 03-servers || { echo "ERROR: Missing 03-servers dir"; exit 1; }

terraform init                          # Init backend and providers
terraform apply -auto-approve           # Build server module

cd .. || exit

# ------------------------------------------------------------------------------------------------
# Build Validation
# ------------------------------------------------------------------------------------------------
# Confirms the AD, AMI, and EC2 servers are functional. May run DNS checks,
# XRDP checks, AD join verification, and instance health checks.
# ------------------------------------------------------------------------------------------------
echo "NOTE: Running build validation..."
./validate.sh

echo "NOTE: Infrastructure build complete."
# ================================================================================================
# End of Script
# ================================================================================================
