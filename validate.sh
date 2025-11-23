#!/bin/bash
# --------------------------------------------------------------------------------------------------
# Description:
# This script queries AWS EC2 for instances tagged with specific names and outputs their
# associated public DNS names. It is primarily used to quickly locate endpoints for 
# Windows and Linux AD instances deployed in AWS.
#
# REQUIREMENTS:
#   - AWS CLI installed and configured with credentials/permissions.
#   - Instances must be tagged with:
#       * Name = windows-ad-instance
#       * Name = mate-instance
# --------------------------------------------------------------------------------------------------

# --------------------------------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------------------------------
AWS_DEFAULT_REGION="us-east-1"   # AWS region where instances are deployed

# --------------------------------------------------------------------------------------------------
# Lookup Windows AD Instance
# --------------------------------------------------------------------------------------------------
windows_dns=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=windows-ad-admin" \
  --query 'Reservations[].Instances[].PublicDnsName' \
  --output text)

if [ -z "$windows_dns" ]; then
  echo "WARN: No Windows AD instance found with tag Name=windows-ad-admin"
else
  echo "NOTE: Windows Instance FQDN: $(echo $windows_dns | xargs)"
fi

# --------------------------------------------------------------------------------------------------
# Lookup Linux AD Instance
# --------------------------------------------------------------------------------------------------
linux_dns=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=mate-instance" \
  --query 'Reservations[].Instances[].PublicDnsName' \
  --output text)

if [ -z "$linux_dns" ]; then
  echo "WARN: No Linux AD instance found with tag Name=mate-instance"
else
  echo "NOTE: MATE Desktop Instance FQDN: $(echo $linux_dns | xargs)"
fi
