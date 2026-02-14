# ================================================================================
# FILE: main.tf
# ================================================================================
#
# Purpose:
#   Define core Terraform provider configuration for the environment.
#
# Design:
#   - Configure AWS provider with target deployment region.
#   - Region may be parameterized in larger environments, but is
#     explicitly defined here for simplicity and clarity.
#
# ================================================================================


# ================================================================================
# SECTION: AWS Provider Configuration
# ================================================================================

# Configure AWS provider for target deployment region.
provider "aws" {
  region = "us-east-1"
}
