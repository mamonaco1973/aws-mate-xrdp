# Generate a random password for the Active Directory (AD) Administrator
resource "random_password" "admin_password" {
  length           = 24    # Set password length to 24 characters
  special          = true  # Include special characters in the password
  override_special = "_-." # Limit special characters to this set
}

# Create an AWS Secrets Manager secret to store AD Admin credentials
resource "aws_secretsmanager_secret" "admin_secret" {
  name        = "admin_ad_credentials" # Name of the secret
  description = "AD Admin Credentials" # Description for reference

  lifecycle {
    prevent_destroy = false # Allow secret deletion if necessary
  }
}

# Store the admin credentials in AWS Secrets Manager with a versioned secret
resource "aws_secretsmanager_secret_version" "admin_secret_version" {
  secret_id = aws_secretsmanager_secret.admin_secret.id # Reference the secret
  secret_string = jsonencode({
    username = "${var.netbios}\\Admin"               # AD username
    password = random_password.admin_password.result # Generated password
  })
}

# ================================================================================================
# Memorable Word List
# ================================================================================================

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

# ================================================================================================
# User Accounts to Generate
# ================================================================================================
locals {
  ad_users = {
    jsmith = "John Smith"
    rpatel = "Raj Patel"
    akumar = "Amit Kumar"
    edavis = "Emily Davis"
  }
}

# ================================================================================================
# Random Word (one per user)
# ================================================================================================
resource "random_shuffle" "word" {
  for_each     = local.ad_users
  input        = local.memorable_words
  result_count = 1
}

# ================================================================================================
# Random 6-digit number (one per user)
# ================================================================================================
resource "random_integer" "num" {
  for_each = local.ad_users
  min      = 100000
  max      = 999999
}

# ================================================================================================
# Build the Password: <word><number>
# ================================================================================================
locals {
  passwords = {
    for user, fullname in local.ad_users :
    user => "${random_shuffle.word[user].result[0]}-${random_integer.num[user].result}"
  }
}

# ================================================================================================
# Create AWS Secret + Version for Each User
# ================================================================================================
resource "aws_secretsmanager_secret" "user_secret" {
  for_each    = local.ad_users
  name        = "${each.key}_ad_credentials"
  description = "${each.value}'s AD Credentials"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "user_secret_version" {
  for_each  = local.ad_users
  secret_id = aws_secretsmanager_secret.user_secret[each.key].id

  secret_string = jsonencode({
    username = "${each.key}@${var.dns_zone}"
    password = local.passwords[each.key]
  })
}
