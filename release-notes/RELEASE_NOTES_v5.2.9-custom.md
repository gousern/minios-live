# Release v5.2.9-custom

- Revert OverlayFS + toram=full default (restores AUFS default behavior).
- Add `KERNEL_AUFS="false"` to `linux-live/build.conf`.
