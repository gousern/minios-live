# Release v5.2.10

- Set OverlayFS as the default union filesystem.
- AUFS remains available via the `union=aufs` kernel parameter.
- Fall back to AUFS when `union=overlayfs` is requested on a kernel without
  the overlay module, instead of aborting the boot.
- Pin overlay mount options (`index=off`, `metacopy=off`, `redirect_dir=on`)
  and add `volatile` when the upper layer is memory backed.
- Refuse to build an overlay union when no squashfs bundles are found.
- Adopt a pre-created ext4 changes image, e.g. `mkfs.ext4 -L persistent
  minios.dat`, as the persistence store.
