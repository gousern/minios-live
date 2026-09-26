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
