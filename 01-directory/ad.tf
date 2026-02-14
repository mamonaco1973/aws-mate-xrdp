# ================================================================================
# SECTION: Mini Active Directory (mini-ad) Module Invocation
# ================================================================================
#
# Purpose:
#   Invoke the reusable "mini-ad" module to provision an Ubuntu-based
#   AD Domain Controller. Provide networking, DNS, and authentication
#   inputs and supply user account definitions via a rendered JSON blob.
#
# Notes:
#   - users_json is rendered from a local template file and passed into
#     the module for bootstrap-time user creation.
#   - depends_on ensures NAT and private routing exist before the AD VM
#     begins provisioning (package repos, updates, etc.).
#
# ================================================================================

module "mini_ad" {
  source            = "github.com/mamonaco1973/module-aws-mini-ad"
  netbios           = var.netbios
  vpc_id            = aws_vpc.ad-vpc.id
  realm             = var.realm
  users_json        = local.users_json
  user_base_dn      = var.user_base_dn
  ad_admin_password = random_password.admin_password.result
  dns_zone          = var.dns_zone
  subnet_id         = aws_subnet.ad-subnet.id

  depends_on = [
    aws_nat_gateway.ad_nat,
    aws_route_table_association.rt_assoc_ad_private
  ]
}

# ================================================================================
# SECTION: Render users_json Template Payload
# ================================================================================
#
# Purpose:
#   Render ./scripts/users.json.template into a single JSON string used
#   by the mini-ad bootstrap process to create demo/test user accounts.
#
# Design:
#   - Template variables are replaced at apply time using templatefile().
#   - User passwords are injected from local.passwords (generated earlier).
#   - The rendered blob is passed to the module as local.users_json.
#
# ================================================================================

locals {
  users_json = templatefile("./scripts/users.json.template", {
    USER_BASE_DN   = var.user_base_dn
    DNS_ZONE       = var.dns_zone
    REALM          = var.realm
    NETBIOS        = var.netbios
    jsmith_password = local.passwords["jsmith"]
    edavis_password = local.passwords["edavis"]
    rpatel_password = local.passwords["rpatel"]
    akumar_password = local.passwords["akumar"]
  })
}
