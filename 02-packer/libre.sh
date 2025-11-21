#!/bin/bash
set -e

# ================================================================================
# LibreOffice Installation Script (DEB Version, No Snap)
# ================================================================================
# Description:
#   Installs the full LibreOffice productivity suite on Ubuntu 24.04 using the
#   native DEB packages from Ubuntu's official APT repositories. This avoids the
#   Snap-based distribution entirely and ensures proper desktop integration.
#
# Notes:
#   - apt-get is used to maintain a stable scripting interface.
#   - Includes libreoffice-gnome for improved theme and UI integration.
#   - Script exits immediately on any failure due to 'set -e'.
# ================================================================================

# ================================================================================
# Step 1: Update the package index
# ================================================================================
echo "NOTE: Updating package index..."
sudo apt-get update -y

# ================================================================================
# Step 2: Install LibreOffice components
# ================================================================================
echo "NOTE: Installing LibreOffice (full suite)..."
sudo apt-get install -y \
  libreoffice \
  libreoffice-gnome \
  libreoffice-common

# ================================================================================
# Step 3: Confirm installation
# ================================================================================
echo "NOTE: Installation complete."
libreoffice --version
