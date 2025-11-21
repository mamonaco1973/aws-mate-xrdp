#!/bin/bash
# ================================================================================================
# AD + Server Infrastructure Teardown Script
# ================================================================================================
# Description:
#   Automates a controlled teardown of AWS infrastructure:
#     1. Removes EC2 server instances created by Terraform.
#     2. Deletes Packer-built AMIs and snapshots matching project patterns.
#     3. Removes AD Domain Controller, deletes AD secrets, and runs AD destroy.
#
# IMPORTANT:
#   - Secrets are removed with --force-delete-without-recovery (no restore).
#   - AWS CLI must be configured with permissions for EC2 and Secrets Manager.
#   - Terraform must be installed and initialized in each module directory.
#   - Run only when you intend to fully remove all deployed resources.
#
# Exit Codes:
#   - 0 : Success.
#   - 1 : Failure due to missing dirs or Terraform/AWS CLI errors.
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"   # Region for deployed resources
set -e                                  # Exit on any non-zero command

# ------------------------------------------------------------------------------------------------
# Phase 1: Destroy EC2 Server Instances
# ------------------------------------------------------------------------------------------------
# This phase removes EC2 server instances defined in the server Terraform
# module. All EC2 resources in 03-servers are destroyed automatically.
# ------------------------------------------------------------------------------------------------
echo "NOTE: Destroying EC2 server instances..."

cd 03-servers || { echo "ERROR: Missing 03-servers dir"; exit 1; }

terraform init                          # Initialize backend and providers
terraform destroy -auto-approve         # Destroy server resources

cd .. || exit                           # Return to repo root

# ------------------------------------------------------------------------------------------------
# Phase 2: Deregister AMIs and delete snapshots
# ------------------------------------------------------------------------------------------------
# This phase deletes all project AMIs, including those created by Packer.
# AMIs named with the xubuntu_ami* pattern are discovered and removed. Any
# snapshots referenced by these AMIs are also deleted to prevent leaks.
# ------------------------------------------------------------------------------------------------
echo "NOTE: Deregistering project AMIs and deleting snapshots..."

for ami_id in $(aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=xubuntu_ami*" \
    --query "Images[].ImageId" \
    --output text); do

    for snapshot_id in $(aws ec2 describe-images \
        --image-ids "$ami_id" \
        --query "Images[].BlockDeviceMappings[].Ebs.SnapshotId" \
        --output text); do

        echo "NOTE: Deregistering AMI: $ami_id"
        aws ec2 deregister-image --image-id "$ami_id"

        echo "NOTE: Deleting snapshot: $snapshot_id"
        aws ec2 delete-snapshot --snapshot-id "$snapshot_id"
    done
done

# ------------------------------------------------------------------------------------------------
# Phase 3: Destroy AD Instance and Related Resources
# ------------------------------------------------------------------------------------------------
# This phase deletes AD-related AWS Secrets Manager items and destroys the
# AD Domain Controller via Terraform. Secrets are removed permanently with
# no recovery window.
# ------------------------------------------------------------------------------------------------
echo "NOTE: Deleting AD secrets..."

aws secretsmanager delete-secret --secret-id "akumar_ad_credentials" \
    --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "jsmith_ad_credentials" \
    --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "edavis_ad_credentials" \
    --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "rpatel_ad_credentials" \
    --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "admin_ad_credentials" \
    --force-delete-without-recovery

echo "NOTE: Destroying AD Terraform resources..."

cd 01-directory || { echo "ERROR: Missing 01-directory dir"; exit 1; }

terraform init
terraform destroy -auto-approve

cd .. || exit

# ------------------------------------------------------------------------------------------------
# Completion
# ------------------------------------------------------------------------------------------------
echo "NOTE: Infrastructure teardown complete."
# ================================================================================================
# End of Script
# ================================================================================================
