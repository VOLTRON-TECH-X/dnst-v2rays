#!/bin/bash
set -e

# Must be root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

echo "Installing VOLTRON TECH DNSTT + V2RAY..."

# URLs (IPv4 forced to avoid GitHub IPv6 issues)
MENU_URL="https://raw.githubusercontent.com/VOLTRON-TECH-X/dnst-v2rays/refs/heads/main/menu.sh"

# Install menu
wget -4 -q -O /usr/local/bin/menu "$MENU_URL"
chmod +x /usr/local/bin/menu

echo "Applying VOLTRON-TECH V2Ray configuration..."

# ============================================================
# HAKUNA SSH CONFIG — V2Ray ni backend pekee
# ============================================================
# V2Ray install inafanyika kupitia menu (option 12)
# Hakuna sshd_config modification

# ============================================================
# RUN INITIAL SETUP
# ============================================================
bash /usr/local/bin/menu --install-setup

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  ✅ Installation complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  📌 Type 'menu' to start."
echo ""
echo "  📋 Next steps:"
echo "     1. Run: menu"
echo "     2. Choose: 12) Install DNSTT + V2Ray"
echo "     3. Follow the installation wizard"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
