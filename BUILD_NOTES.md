# Build Notes

Personal notes and lessons learned from building MiniOS.

## 2024 - CI Cleanup Pitfall

### Problem
The `build-minios.yml` workflow had an "Extra cleanup" section that was **destroying** the XFCE desktop:

```bash
# ❌ This was deleting everything:
find /usr/share/fonts ... -delete
find /usr/share/icons ... -exec rm -rf {} \;
find /usr/share/themes ... -exec rm -rf {} \;
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/applications/*.desktop
```

### Symptoms
- XFCE theme completely gone (no MiniOS branding)
- Firefox fonts broken (Inter, JetBrains Mono missing)
- Cloudflare WARP and other tools missing from menu
- All .desktop files deleted (apps invisible in menus)

### Root Cause
The cleanup was too aggressive - it removed:
- All fonts (breaking rendering)
- All icons except hicolor/default/Adwaita (breaking themes)
- All themes except Default/Adwaita (breaking XFCE)
- All backgrounds (removing MiniOS wallpapers)
- All .desktop files (breaking application launchers)

### Fix
Removed the destructive lines. Safe cleanup preserved:
- apt cache, logs, temp files
- man pages, docs, info
- Unused locales

### Lesson
**Always test ISO output after workflow changes.** The cleanup was added to reduce ISO size but broke the desktop experience.

---

## Module System Overview

### skip_conditions.conf
Each module can have a `skip_conditions.conf` that skips building when conditions match:

- `05-apps/skip_conditions.conf`: Skips for `minimum` and `standard` variants
- `01-kernel/skip_conditions.conf`: Skips when `INSTALL_KERNEL=false`

### Package Variant Flow
```
standard  → skips 05-apps (no Cloudflare WARP, no extra tools)
toolbox   → includes 05-apps (Cloudflare WARP, DKMS, dev tools)
ultra     → includes everything (LibreOffice, GIMP, etc.)
```

### Key Modules
| Module | Purpose | Key Contents |
|--------|---------|--------------|
| 00-core | Base system | minios-tools (apt2sb, etc.) |
| 01-kernel | Kernel + DKMS | broadcom-sta-dkms, zfs-dkms |
| 02-firmware | Hardware firmware | linux-firmware-* |
| 03-gui-base | X11 + fonts | Inter, JetBrains Mono fonts |
| 04-xfce-desktop | XFCE + theme | MiniOS backgrounds, config |
| 05-apps | Extra applications | Cloudflare WARP, dev tools |
| 10-firefox | Firefox ESR | Browser + locales |

### rootcopy-install
Files in `rootcopy-install/` are copied to the chroot during build. This is how:
- Fonts get to `/usr/share/fonts/`
- Theme configs get to `/etc/skel/.config/`
- Backgrounds get to `/usr/share/backgrounds/`

---

## Useful Commands

```bash
# Build locally
sudo ./minios-live -                  # Full build
sudo ./minios-live build-chroot       # Just chroot phase
sudo ./minios-live build-iso          # Just ISO creation

# Check what's in a squashfs
unsquashfs -l image.sb | grep -E "font|theme|background"

# Test in QEMU
qemu-system-x86_64 -cdrom output.iso -m 4G -enable-kvm
```

---

## User Workflow

- **Fork**: User maintains a personal fork of minios-live
- **Build trigger**: GitHub Actions, triggered manually from `.github/workflows/`
- **Workflow**: `trixie-xfce-toolbox-amd64.yml` - builds XFCE ISO with toolbox packages
- **Verify**: Download ISO from GitHub releases, test in QEMU or VM

### How to Make Changes
1. Edit files in your fork
2. Push to your fork
3. Trigger build in GitHub Actions
4. Wait ~30-60 min for build to complete
5. Download ISO from releases
6. Test in QEMU: `qemu-system-x86_64 -cdrom output.iso -m 4G -enable-kvm`

### Quick Verification After Build
```bash
# Mount the ISO and check for key files
sudo mkdir /mnt/iso
sudo mount -o loop output.iso /mnt/iso

# Check squashfs contents
sudo unsquashfs -l /mnt/iso/casper/filesystem.squashfs | grep -E "font|theme|background|cloudflare"

# Check for XFCE theme
sudo unsquashfs -l /mnt/iso/casper/filesystem.squashfs | grep -i "minios"

# Check for fonts
sudo unsquashfs -l /mnt/iso/casper/filesystem.squashfs | grep -E "Inter|JetBrains"
```

---

## Project Structure (Quick Reference)

```
minios-live/
├── linux-live/
│   ├── build.conf              # Main build config
│   ├── minioslib               # Core build functions
│   ├── condinapt               # Conditional package installer
│   ├── environments/
│   │   └── xfce/               # XFCE environment config
│   │       ├── 01-minimal/     # Minimal packages
│   │       ├── 02-standard/    # Standard packages  
│   │       ├── 03-full/        # Full packages
│   │       └── 05-apps/        # Extra apps (Cloudflare WARP)
│   └── scripts/
│       ├── 00-core/            # Base system
│       ├── 01-kernel/          # Kernel + DKMS
│       ├── 02-firmware/        # Hardware firmware
│       ├── 03-gui-base/        # X11 + fonts
│       ├── 04-xfce-desktop/    # XFCE + theme
│       ├── 05-apps/            # Extra applications
│       └── 10-firefox/         # Firefox ESR
├── .github/workflows/
│   ├── build-minios.yml        # Main CI (⚠️ has cleanup logic)
│   └── trixie-xfce-*.yml       # Specific builds
└── BUILD_NOTES.md              # This file
```

---

## Common Issues & Fixes

### Issue: Apps missing from menu
**Cause**: `.desktop` files deleted by cleanup
**Fix**: Check `build-minios.yml` cleanup section

### Issue: Fonts broken
**Cause**: Fonts deleted or not installed
**Fix**: Check `03-gui-base` and `rootcopy-install` directories

### Issue: Cloudflare WARP missing
**Cause**: Using `standard` variant (skips 05-apps)
**Fix**: Use `toolbox` or `ultra` variant

### Issue: Theme not applied
**Cause**: `04-xfce-desktop/install` had `rm -rf /usr/share/backgrounds` which deleted MiniOS backgrounds before they were copied
**Fix**: Removed the destructive `rm -rf` line

### Issue: Cloudflare WARP missing
**Cause**: Cloudflare repository wasn't added during build (only at boot time via `system-provision.sh`)
**Fix**: Added Cloudflare WARP repository setup to `05-apps/install` before `condinapt` runs

---

## Important Files to Monitor

- `.github/workflows/build-minios.yml` - CI cleanup logic
- `linux-live/build.conf` - Package variant settings
- `linux-live/scripts/*/rootcopy-install/` - Files copied to ISO
- `linux-live/environments/xfce/05-apps/` - Extra applications list
- `linux-live/scripts/07-customs/` - **Your custom packages module**

---

## Custom Module: 07-customs

### Structure
```
linux-live/scripts/07-customs/
├── packages.list          # Your custom packages (from dotfiles/system-provision.sh)
├── install                # Build script
└── rootcopy-install/      # Files to copy to ISO
    └── usr/local/bin/     # Scripts (macos_style_keyboard.sh)
```

### Packages Included (from dotfiles/system-provision.sh)
- Base: gawk, fontconfig, fonts-noto-color-emoji, git, tree, curl, wget, vim
- XFCE/X11: xinput, xfce4-genmon-plugin, libnotify-bin
- Fcitx5: fcitx5, fcitx5-chewing
- Media: mpv, mpv-mpris, ffmpeg, socat, jq, playerctl
- Audio: pamixer
- Android: adb, openssh-client
- Cloudflare WARP (with repository setup)
- mise (via curl)

### Files Included (from dotfiles)
- `accels.scm` → `/etc/skel/.config/xfce4/terminal/` (Firefox/terminal shortcuts)
- `xfce4-keyboard-shortcuts.xml` → `/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/` (XFCE shortcuts)
- `macos_style_keyboard.sh` → `/usr/local/bin/` (keyboard setup script)
- `screen.sh` → `/usr/local/bin/` (resolution fix script)
- `im.sh` → `/usr/local/bin/` (Fcitx5 verification and setup)
- `macos_style_firefox_fonts.sh` → `/usr/local/bin/` (PingFang font for Firefox)

### How to Add Packages
1. Edit `linux-live/scripts/07-customs/packages.list`
2. Add package names (one per line)
3. Push to your fork
4. Trigger build

### How to Add Files (fonts, configs, etc.)
1. Put files in `linux-live/scripts/07-customs/rootcopy-install/`
2. Mirror the target path (e.g., `usr/share/fonts/` for fonts)
3. Push and build

### Build Verification
The workflow now shows:
- Available modules
- 07-customs contents
- Squashfs contents after build
- Cloudflare WARP and fonts check
