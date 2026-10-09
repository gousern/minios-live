# Release v5.2.13-toolbox

- Boot menus now offer the union filesystem as a **choice** instead of
  hardcoding one for everybody: **AUFS boots by default**, OverlayFS is one
  selection away.
- GRUB (UEFI): the five AUFS entries stay on the top-level menu; the same five
  entries live one level deeper in a `Boot with OverlayFS (default: AUFS)`
  submenu.
- SYSLINUX (BIOS): every entry carries `union=aufs`, plus a
  `Union filesystem: switch to OverlayFS` entry that links to a mirrored
  `lang/<lang>-overlayfs.cfg` menu where every entry carries
  `union=overlayfs` and links back to the AUFS menu.
- Kernel command line unchanged: without `union=` the runtime still picks AUFS
  when the kernel has it and falls back to OverlayFS otherwise, so an explicit
  `union=overlayfs` / `union=aufs` keeps working.
- Both menu sets are generated from a single source per filesystem, so they
  cannot drift apart; guarded by `linux-live/tests/boot_config.bats` and the
  union default test in `linux-live/initramfs/tests/persistence_behavior.bats`.

Why: with OverlayFS forced as the default, this machine stalled for 5-10
minutes at boot while AUFS came up promptly, so the boot menu now lets the
user pick the union filesystem per boot.
