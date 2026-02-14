# ================================================================================
# FILE: accounts.tf
# ================================================================================
#
# Purpose:
#   Generate credentials for the Active Directory Administrator and a
#   defined set of AD users. Store all credentials securely in AWS
#   Secrets Manager.
#
# Design:
#   - Administrator password generated at Terraform apply time.
#   - User passwords generated using memorable word + 6-digit number.
#   - Credentials stored as versioned secrets.
#   - No credentials exposed via Terraform outputs.
#   - Secrets permitted to be destroyed during teardown.
#
# Security Notes:
#   - Admin password length set to 24 characters.
#   - Special characters restricted for automation safety.
#   - User passwords deterministic format: <word>-<number>.
#
# ================================================================================


# ================================================================================
# SECTION: Active Directory Administrator Credential
# ================================================================================

# Generate strong random password for AD Administrator account.
resource "random_password" "admin_password" {
  length           = 24
  special          = true
  override_special = "_-."
}

# Create Secrets Manager container for Administrator credentials.
resource "aws_secretsmanager_secret" "admin_secret" {
  name        = "admin_ad_credentials"
  description = "Active Directory Administrator credentials"

  lifecycle {
    prevent_destroy = false
  }
}

# Store Administrator credentials as versioned secret payload.
resource "aws_secretsmanager_secret_version" "admin_secret_version" {
  secret_id = aws_secretsmanager_secret.admin_secret.id

  secret_string = jsonencode({
    username = "${var.netbios}\\Admin"
    password = random_password.admin_password.result
  })
}


# ================================================================================
# SECTION: Active Directory User Credentials
# ================================================================================


# --------------------------------------------------------------------------------
# Subsection: Memorable Word Source List
# --------------------------------------------------------------------------------

locals {
  memorable_words = [
    "bright",
    "simple",
    "orange",
    "window",
    "little",
    "people",
    "friend",
    "yellow",
    "animal",
    "family",
    "circle",
    "moment",
    "summer",
    "button",
    "planet",
    "rocket",
    "silver",
    "forest",
    "stream",
    "butter",
    "castle",
    "wonder",
    "gentle",
    "driver",
    "coffee"
  ]
}


# --------------------------------------------------------------------------------
# Subsection: User Definitions
# --------------------------------------------------------------------------------

locals {
  ad_users = {
    jsmith = "John Smith"
    rpatel = "Raj Patel"
    akumar = "Amit Kumar"
    edavis = "Emily Davis"
  }
}


# --------------------------------------------------------------------------------
# Subsection: Password Generation Components
# --------------------------------------------------------------------------------

# Select one random memorable word per user.
resource "random_shuffle" "word" {
  for_each     = local.ad_users
  input        = local.memorable_words
  result_count = 1
}

# Generate one random 6-digit number per user.
resource "random_integer" "num" {
  for_each = local.ad_users
  min      = 100000
  max      = 999999
}

# Construct final password as: <word>-<number>.
locals {
  passwords = {
    for user, fullname in local.ad_users :
    user => format(
      "%s-%d",
      random_shuffle.word[user].result[0],
      random_integer.num[user].result
    )
  }
}

# --------------------------------------------------------------------------------
# Subsection: Per-User Secrets
# --------------------------------------------------------------------------------

# Create Secrets Manager container for each AD user.
resource "aws_secretsmanager_secret" "user_secret" {
  for_each    = local.ad_users
  name        = "${each.key}_ad_credentials_mate"
  description = "${each.value} AD credentials"

  lifecycle {
    prevent_destroy = false
  }
}

# Store user credentials as versioned secret payload.
resource "aws_secretsmanager_secret_version" "user_secret_version" {
  for_each  = local.ad_users
  secret_id = aws_secretsmanager_secret.user_secret[each.key].id

  secret_string = jsonencode({
    username = "${each.key}@${var.dns_zone}"
    password = local.passwords[each.key]
  })
}
