#!/bin/bash
# Custom setup for MiniOS Toolbox Edition
# This script runs during ISO build to configure keyboard shortcuts, etc.

set -e

# Only run for toolbox/ultra editions on amd64
if [ "$PACKAGE_VARIANT" != "toolbox" ] && [ "$PACKAGE_VARIANT" != "ultra" ]; then
    echo "Skipping custom-setup (not toolbox/ultra edition)"
    exit 0
fi

if [ "$DISTRIBUTION_ARCH" != "amd64" ]; then
    echo "Skipping custom-setup (not amd64)"
    exit 0
fi

echo "=== Custom Setup: Toolbox Edition ==="

# ─── 1. Set up keyboard defaults in /etc/default/keyboard ──────────────────
echo "Configuring keyboard defaults..."
cat > /etc/default/keyboard << 'EOF'
# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT="mac"
XKBOPTIONS="ctrl:swapcaps,altwin:swap_alt_win"

VARIANTIGNORE=""
LAYOUTIGNORE=""
MODELIGNORE=""
OPTIONSIGNORE=""
EOF

# ─── 2. Set up XKB configuration ──────────────────────────────────────────
echo "Configuring XKB layout..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << 'EOF'
Section "InputClass"
    Identifier "keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
    Option "XkbVariant" "mac"
    Option "XkbOptions" "ctrl:swapcaps,altwin:swap_alt_win"
EndSection
EOF

# ─── 3. Set up default keyboard for live user ─────────────────────────────
echo "Setting up keyboard for live user..."
mkdir -p /etc/skel/.config/autostart

cat > /etc/skel/.config/autostart/apply-keyboard.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Apply Keyboard Settings
Comment=Apply macOS-style keyboard mapping and Firefox fonts
Exec=/home/live/bin/macos_style_firefox_fonts.sh
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# ─── 4. Set up default resolution for live user ────────────────────────────
cat > /etc/skel/.config/autostart/set-resolution.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Set Resolution
Comment=Set display to 1280x800@60Hz
Exec=/bin/bash -c "sleep 1 && xrandr --output $(xrandr --query | awk '/ connected/{print $1; exit}') --mode 1280x800 2>/dev/null || true"
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# ─── 5. Fcitx5 configuration for live user ────────────────────────────────
echo "Configuring Fcitx5..."
mkdir -p /etc/skel/.config/fcitx5

cat > /etc/skel/.config/fcitx5/profile << 'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=chewing

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=chewing
Layout=

[GroupOrder]
0=Default
EOF

# ─── 6. Environment variables for input method ─────────────────────────────
cat >> /etc/skel/.profile << 'EOF'

# Fcitx5 input method
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF

# ─── 7. Create ~/bin directory ────────────────────────────────────────────
mkdir -p /etc/skel/bin

echo "=== Custom Setup Complete ==="
