#!/bin/bash
# ================================================================================
# FILE: validate.sh
# ================================================================================
#
# Purpose:
#   Validate the deployment by locating key instance endpoints and
#   printing a clean, aligned summary for quick copy/paste access.
#
# What This Script Does:
#   - Queries EC2 for instances by Name tag.
#   - Extracts Public DNS names (for RDP / SSH / XRDP access paths).
#
# Requirements:
#   - AWS CLI installed and configured with appropriate permissions.
#   - Instances must be tagged:
#       * Name = windows-ad-admin
#       * Name = mate-instance
#
# Output:
#   - Prints a short banner and aligned key/value lines.
#
# ================================================================================

set -euo pipefail

# ================================================================================
# SECTION: Configuration
# ================================================================================

export AWS_DEFAULT_REGION="us-east-1"

# ================================================================================
# SECTION: Helpers
# ================================================================================

get_public_dns_by_name_tag() {
  local name_tag="$1"

  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${name_tag}" \
    --query "Reservations[].Instances[].PublicDnsName" \
    --output text | xargs
}

print_kv() {
  local key="$1"
  local value="$2"

  printf "%-28s %s\n" "${key}:" "${value}"
}

# ================================================================================
# SECTION: Lookup Endpoints
# ================================================================================

windows_dns="$(get_public_dns_by_name_tag "mate-ad-admin")"
mate_dns="$(get_public_dns_by_name_tag "mate-instance")"

# ================================================================================
# SECTION: Output
# ================================================================================

echo "==============================================================================="
echo "VALIDATION RESULTS: AD + MATE DESKTOP"
echo "==============================================================================="
echo

if [ -z "${windows_dns}" ]; then
  print_kv "Windows AD Admin Host" "NOT FOUND (Name=windows-ad-admin)"
else
  print_kv "Windows AD Admin Host" "${windows_dns}"
fi

if [ -z "${mate_dns}" ]; then
  print_kv "MATE Desktop Host" "NOT FOUND (Name=mate-instance)"
else
  print_kv "MATE Desktop Host" "${mate_dns}"
fi

echo
echo "==============================================================================="
