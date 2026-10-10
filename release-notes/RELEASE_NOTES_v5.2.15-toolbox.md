# Release v5.2.15-toolbox

- First boot on an OverlayFS union no longer stalls. live-config runs
  `chown -R` over the live user's home on every boot, and the image baked
  about 1 GB of root-owned files into `/home/live` (mise toolchains, skel
  seed, fonts). OverlayFS mounts with `metacopy=off`, so that chown copied
  every file up in full — measured at 90 seconds for 981 MB across 11,276
  files, with `live-config.service` running for 2 m 22 s and the kernel log
  completely silent in between. The same chown also copies up files whose
  owner already matches, so even a no-op chown is not free.
- Two matching changes: the module that writes `/home/live` now bakes the
  ownership in (uid/gid 1000, which is what the first-boot `user-setup`
  creates), and the unconditional `chown -R` in `0030-user-setup` is
  replaced by a `find` guard that only chowns entries that are actually
  misowned. On a correctly-owned tree nothing is copied up at all.
- Symlink ownership is handled the same way the old `chown -R` did it: the
  link itself changes owner, never its target.
- `verify-iso.sh` gained the assertions that would have caught this. It
  never checked `/home/live` ownership and never checked the GRUB menu at
  all. It now verifies baked ownership across every module, that the
  guarded chown is present and the plain `chown -R` is gone, and that the
  AUFS and OverlayFS entries exist in both the GRUB and the SYSLINUX menus.
- The OverlayFS boot menu, the persistence-image entries and the
  English-only menus shipped in v5.2.14-toolbox are unchanged and are now
  covered by the ISO checks.

Why: the OverlayFS path added in v5.2.14-toolbox was correct but unusable
on slower machines, because a 90 second pause inside a boot with no output
looks like a hang. The union now boots in the same time as AUFS.