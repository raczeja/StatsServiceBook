#!/usr/bin/env bash
set -euo pipefail

# Install PowerShell (pwsh) on Ubuntu-based Codespaces/devcontainer images.
# Run as root (in Codespaces postCreateCommand runs as root) or with sudo.

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root or via sudo."
  exit 1
fi

TMP_DEB="/tmp/packages-microsoft-prod.deb"
curl -fsSL "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" -o "$TMP_DEB"
dpkg -i "$TMP_DEB"
rm -f "$TMP_DEB"
apt-get update
apt-get install -y --no-install-recommends powershell

echo "PowerShell installed. Run 'pwsh' to start it." 
