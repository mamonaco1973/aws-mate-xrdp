#!/bin/bash
# ================================================================================
# AD + Server Infrastructure Teardown Script
# ================================================================================
#
# Purpose:
#   Perform a controlled teardown of all infrastructure created by the
#   AD + MATE deployment workflow.
#
# Teardown Phases:
#   1. Destroy EC2 server instances (Terraform: 03-servers).
#   2. Deregister project AMIs and delete associated snapshots.
#   3. Delete AD-related Secrets Manager entries (no recovery).
#   4. Destroy AD infrastructure (Terraform: 01-directory).
#
# WARNING:
#   - Secrets are deleted with --force-delete-without-recovery.
#   - AMIs and snapshots are permanently removed.
#   - Run only when you intend to fully remove all resources.
#
# Requirements:
#   - AWS CLI configured with EC2 and Secrets Manager permissions.
#   - Terraform installed and initialized in module directories.
#
# Exit Codes:
#   - 0: Success.
#   - 1: Missing directories or Terraform/AWS CLI failure.
#
# ================================================================================

set -euo pipefail

# ================================================================================
# SECTION: Configuration
# ================================================================================

export AWS_DEFAULT_REGION="us-east-1"

# ================================================================================
# SECTION: Phase 1 - Destroy EC2 Server Instances
# ================================================================================

# Destroy all EC2 resources defined in the 03-servers module.
echo "NOTE: Destroying EC2 server instances..."

cd 03-servers || { echo "ERROR: Missing 03-servers dir"; exit 1; }

terraform init
terraform destroy -auto-approve

cd .. || exit

# ================================================================================
# SECTION: Phase 2 - Deregister AMIs and Delete Snapshots
# ================================================================================

# Remove all project AMIs matching name pattern "mate_ami*".
# Also delete associated EBS snapshots to prevent orphaned storage.
echo "NOTE: Deregistering project AMIs and deleting snapshots..."

for ami_id in $(aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=mate_ami*" \
    --query "Images[].ImageId" \
    --output text); do

    # Retrieve snapshots referenced by this AMI.
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

# ================================================================================
# SECTION: Phase 3 - Destroy AD Infrastructure and Secrets
# ================================================================================

# Permanently delete AD-related Secrets Manager entries.
echo "NOTE: Deleting AD secrets..."

aws secretsmanager delete-secret --secret-id "akumar_ad_credentials_mate" \
  --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "jsmith_ad_credentials_mate" \
  --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "edavis_ad_credentials_mate" \
  --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "rpatel_ad_credentials_mate" \
  --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "admin_ad_credentials_mate" \
  --force-delete-without-recovery

# Destroy AD Terraform resources.
echo "NOTE: Destroying AD Terraform resources..."

cd 01-directory || { echo "ERROR: Missing 01-directory dir"; exit 1; }

terraform init
terraform destroy -auto-approve

cd .. || exit

# ================================================================================
# SECTION: Completion
# ================================================================================

echo "NOTE: Infrastructure teardown complete."
