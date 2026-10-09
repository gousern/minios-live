# Release v5.2.14-toolbox

- The GRUB menus gain one more entry, **Start MiniOS and create the
  persistence image**, in both the AUFS top-level menu and the OverlayFS
  submenu. Selecting it boots with `perchformat=1`, so the initramfs builds
  the persistence store itself instead of waiting for another operating
  system to `mkfs.ext4` the USB stick.
- The store is found where it actually lives: a blank `minios.dat` candidate
  is formatted in place, and the `.dat` that Ventoy's own configuration names
  is prepared after mounting the Ventoy partition read-write. The freshly
  built image is loop mounted in the very same boot, so persistence starts
  working immediately.
- Formatting only ever happens where there is nothing to lose: a target that
  carries a filesystem **or a partition table** is refused, image files under
  256 MB are refused, and the image is built journal-less with the label
  MiniOS greps for (`mke2fs -q -t ext4 -F -m 0 -O '^has_journal' -L
  persistence`), matching the documented hand-made setup.
- Plain boots are unchanged: without the new entry nothing is written to the
  stick. An already prepared `.dat` labelled `persistence` is picked up
  read-only even when no persistence image was selected in Ventoy, as long as
  the boot asks for persistence.
- SYSLINUX (BIOS) does not carry the new entry yet; GRUB (UEFI) is the
  tested path for this release.
- Covered by six new cases in
  `linux-live/initramfs/tests/persistence_behavior.bats` and the GRUB menu
  expectations in `linux-live/tests/boot_config.bats`.

Why: every re-flash of the stick used to mean booting a different system just
to create an ext4 persistence image. GRUB now offers that as a menu option;
if it is never selected, behaviour is exactly what v5.2.13-toolbox shipped.
