#!/bin/bash
# ================================================================================
# FILE: validate.sh
# ================================================================================
#
# Purpose:
#   Validate the deployment by locating key instance endpoints and
#   printing a clean, aligned summary for quick copy/paste access,
#   including a domain login to sign in with.
#
# What This Script Does:
#   - Queries EC2 for instances by Name tag.
#   - Extracts Public DNS names (for RDP / SSH / XRDP access paths).
#   - Reads jsmith's AD password from Secrets Manager.
#
# Requirements:
#   - AWS CLI installed and configured with appropriate permissions.
#   - Instances must be tagged:
#       * Name = mate-ad-admin
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
desktop_dns="$(get_public_dns_by_name_tag "mate-instance")"

# jsmith is in mcloud-users and linux-admins (sudo on the desktop).
jsmith_password="$(aws secretsmanager get-secret-value \
  --secret-id jsmith_ad_credentials_mate \
  --query SecretString --output text 2>/dev/null | jq -r .password || true)"

# ================================================================================
# SECTION: Output
# ================================================================================

echo "==============================================================================="
echo "VALIDATION RESULTS: AD + MATE DESKTOP"
echo "==============================================================================="
echo

if [ -z "${windows_dns}" ]; then
  print_kv "Windows AD Admin Host" "NOT FOUND (Name=mate-ad-admin)"
else
  print_kv "Windows AD Admin Host" "${windows_dns}"
fi

if [ -z "${desktop_dns}" ]; then
  print_kv "MATE Desktop Host" "NOT FOUND (Name=mate-instance)"
else
  print_kv "MATE Desktop Host" "${desktop_dns}"
fi

echo
if [ -z "${jsmith_password}" ]; then
  print_kv "Sign in" "NOT FOUND (secret jsmith_ad_credentials_mate)"
else
  print_kv "Sign in" "jsmith / ${jsmith_password}"
fi
printf "%-28s %s\n" "" "Desktop: jsmith. Windows: MCLOUD\\jsmith."
printf "%-28s %s\n" "" "Other users: <user>_ad_credentials_mate"
printf "%-28s %s\n" "" "in Secrets Manager."

echo
echo "==============================================================================="