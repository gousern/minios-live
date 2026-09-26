# THEME_DEBUG.md — "MiniOS default theme missing" brain dump

> Purpose: reload this entire investigation in one read. Updated while debugging.
> Companion to `BUILD_NOTES.md` (build lessons) and `AGENTS.md` (rules).

## 1. The complaint

- User built `trixie-xfce-toolbox-amd64` from `.github/workflows/trixie-xfce-toolbox-amd64.yml`
  (fork: `gousern/minios-live`; upstream: `minios-linux/minios-live`).
- ISO: `~/Downloads/minios-trixie-xfce-toolbox-amd64-5.2.0-custom.iso` (1.7 GB, built 2026-09-26).
- Cloudflare WARP / apfs-dkms / broadcom-sta-dkms now install fine (07-customs OK — user confirmed).
- **But: "minios default theme missing on the xfce"** — persists after those fixes.

## 2. What the built ISO actually shows (observed in QEMU, 1280x800)

| Symptom | Evidence | Meaning |
|---|---|---|
| **Black wallpaper** | `xfdesktop` shows pure black from first frame; `/usr/share/backgrounds/minios6-toolbox.jpg` EXISTS in `04` squashfs | backdrop config not applied OR monitor-id mismatch |
| **File System + Floppy icons visible** | desktop shows Home/File System/Trash/Floppy | skel `xfce4-desktop.xml` says `show-filesystem=false`, `show-removable=false` → **NOT applied** → suggests the whole skel `xfce4-desktop.xml` is ignored (defaults: all icons on, no wallpaper) |
| Panel/dock DO render (Applications menu, workspace switcher, clock, bottom dock) | screenshots | some skel config (panel) loads — need to verify which |
| Appfinder window renders light/grey, possibly Greybird-ish | `alt-f2` screenshot | xsettings theme may actually work; needs live `xfconf-query` proof |
| GTK typing eaten (`sendkey x` into focused appfinder entry → nothing) | loop of sendkey + screendump | suspected `GTK_IM_MODULE=fcitx` w/o working fcitx5 (07-customs) |
| Panel clock freezes / session appears to wedge after minutes; lightdm restarts sessions | clock read 19:33 while UTC 19:59+; multiple session states observed | session hang loop — possibly related to same root cause or separate |
| Official 5.1.1 ISO | downloading → ground truth comparison | NOT yet booted/completed |

## 3. Key facts (do NOT re-discover)

### ISO / squashfs layout
- ISO mounted at `/mnt/iso`; modules in `/mnt/iso/minios/*.sb` (aufs layers):
  `00-core, 01-kernel-6.12.107+deb13, 02-firmware, 03-gui-base, 04-xfce-desktop, 05-apps, 06-firefox, 07-customs`.
- Extract: `sudo unsquashfs -f -d /tmp/sq04x /mnt/iso/minios/04-xfce-desktop-amd64.sb`
- **Whiteout check**: `unsquashfs -ll | grep -E "^[cb]"` (plain `-l` HIDES whiteout char-devs!).
  Result: NO whiteouts on skel/backgrounds/icons/themes in ANY module.
  Only whiteout: `05` → `wl.ko` (broadcom replacement, expected).
- `/home` is NOT baked into any squashfs → skel → live user at boot.
- Boot loader/config: `/minios/{config.conf,modules,boot}`; initrd = dracut
  (`/mnt/iso/boot/initrd.img-6.12.107+deb13-amd64`, 60 MB).

### Theme files (all PRESENT in `04` skel, verified in image)
- `/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/`
  - `xsettings.xml` (2285 B, edited 20:12 by 04's xmlstarlet) — Net/ThemeName expected: **Greybird**,
    IconTheme: **elementary-minios-dark** (inherited from elementary-minios), Gtk/IconSizes, fonts Inter 10.
  - `xfce4-desktop.xml` (16210 B, 20:12 = **rewritten by minios6-artwork postinst `configure-xfce-wallpaper`**)
  - `xfwm4.xml`, `xfce4-panel.xml` (4966 B, 20:12), `xfce4-keyboard-shortcuts.xml` (07 later replaces it)
- 04 install (`linux-live/scripts/04-xfce-desktop/install`) edits xsettings/xfwm4 via xmlstarlet (Inter fonts,
  Antialias, hintfull), writes whiskermenu rc with `button-icon=/usr/share/pixmaps/MiniOS-white.svg`,
  writes panel xml (line ~263 in the non-whisker branch). NOTE: line 372 writes keyboard-shortcuts to a
  WRONG path (`/etc/skel/.config/xfconf/...` — missing `xfce4/`).
- Wallpaper writer: `minios6-artwork` package → `configure-xfce-wallpaper` postinst. For trixie writes
  modern XML with monitor list `Virtual-1, Virtual-2, Virtual1, eDP, eDP-1, HDMI-A-0/1, HDMI-1/2, DP-1/2/3,
  LVDS-1, DVI-I-1/2` + `last-image=/usr/share/backgrounds/minios6-toolbox.jpg`, `show-filesystem=false`,
  `show-removable=false`. Repo's own rootcopy xml still references old `minios-wallpaper.jpg`
  (overwritten by postinst — runtime content confirmed = minios6-toolbox.jpg + monitors).
- `minios6-artwork` ships wallpapers/pixmaps only; GTK/icon themes come from other packages
  (Greybird = gtk-theme package, elementary-minios icons in `03-gui-base` — confirmed present).

### QEMU test rig (already running — reuse it!)
- Launch script: `/tmp/qshot/launch.sh` (pid 5950; monitor socket `/tmp/qshot/mon.sock`;
  VNC `127.0.0.1:5901`; screendumps → `/tmp/qshot/*.ppm` → convert with PIL).
- Screenshots: `echo "screendump /tmp/qshot/x.ppm" | socat - unix-connect:/tmp/qshot/mon.sock`
- **Monitor `sendkey` WORKS** (e.g. `sendkey alt-f2` opened Application Finder).
  Key names: `super` is INVALID here → "invalid parameter"; use `ctrl/alt/fN/minus/...`.
- **Monitor `mouse_move` does NOT move the guest cursor** (tested; no framebuffer diff) → clicks unusable.
- **VNC input client `/tmp/qshot/vncinput.py`** written (pure stdlib RFB) but QEMU VNC **auth fails**:
  server offers security `[1]` (None) then returns result=1 "Authentication failed" → input via VNC blocked.
- **SSH into guest FAILS**: hot-added `netdev_add user,id=n1,hostfwd=tcp::2222-:22` + `device_add e1000,netdev=n1`;
  host port 2222 listens but no guest banner → guest sshd/NIC unreachable (NM never configures it).
- **Text console reachable**: earlier a console screenshot showed login banner with
  **default passwords: `root: toor`, `live: evil`** — but `sendkey ctrl-alt-f1/f3` VT switching is now
  blocked (X/logind grabs it).
- Reset guest cleanly: `printf 'system_reset\n' | socat - unix-connect:/tmp/qshot/mon.sock`
- Boot→desktop ≈ 90–110 s; screensaver locks session after ~4–5 min (xfce4-screensaver) — interact FAST.

### Other environment notes
- `gh` works (auth'd; default repo = upstream `minios-linux/minios-live`).
- Official ISO (ground truth): `/home/live/Downloads/minios-trixie-xfce-toolbox-amd64-5.1.1.iso`
  — COMPLETE + **sha256 VERIFIED** vs release asset:
  `ca4f7d25c7d60b83e1fdac45c496a5e94e9ac8bbb87396123f7a1c85e7b29979`.
  Release also has `.sha512` assets for other variants.
- Host git hooks run through mise shims: if `mise ERROR No version is set for shim: jaq` blocks
  a commit, fix with `mise use -g jaq@3.1.1`.
- No `pip`/`uv`/`vncdotool` on host; `python3-pip` not installed. PIL available. `sshpass` available.
- Live passwords for consoles: `live: evil`, `root: toor`.
- Session timeline (UTC): first boot ≈19:30 desktop; `system_reset` ≈19:56; fresh session desktop 20:04,
  alt-f2 worked 20:05, typing dead 20:06, clock later showed 20:03 while UTC 20:12 → clock freeze/hang loop.

## 4. Root-cause hypotheses (ranked, testable)

1. **skel `xfce4-desktop.xml` never reaches/loads into the live user** (→ defaults: black + all icons).
   Test: shell in guest → `cat /home/live/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml`,
   `xfconf-query -c xfce4-desktop -lv`, `xfconf-query -c xsettings -p /Net/ThemeName`.
2. **xfce4-desktop channel rejected/ignored** (property-type/migration issue from artwork postinst XML —
   e.g. `last-settings-migration-version`, `tooltip-size type="double"`).
   Test: same as above + compare with OFFICIAL 5.1.1 ISO content & behavior.
3. **fcitx5 (07-customs) wedges session** (eaten keys; possibly clock/hang loop) — separate from wallpaper,
   but check `07-customs/packages.list` + `.xprofile` `GTK_IM_MODULE=fcitx` (should be `fcitx` for fcitx5? it's valid, but fcitx5 must RUN).
4. QEMU monitor-name not in postinst list (e.g. bochs/simpledrm connector name) → wallpaper only,
   does NOT explain File System icon → weaker.

## 5. Next steps (in order)

1. `sha256sum` official ISO vs release `.sha256` asset; mount it (`sudo mount -o loop`), extract its
   `04` module skel configs → `diff` against ours (xsettings/xfce4-desktop/xfwm4/panel).
2. Boot official ISO in a SECOND qemu (`/tmp/qshot/launch-official.sh`, own monitor socket + VNC port)
   → screenshot: does wallpaper/icons/theme work there?
   - Official OK + ours broken → diff the differing files; fix in repo.
   - Official also black/odd → QEMU headless artifact; verify on real hardware/VMware (user's env has
     open-vm-tools/virtualbox guest utils installed — vmwgfx output names ARE in the monitor list).
3. If guest shell becomes reachable: run the `xfconf-query` commands in §4, capture live channel values.
4. Fix candidates (do NOT apply before proof):
   - ensure `show-filesystem=false` actually lands (`xfconf-query` reset),
   - add QEMU connector names if missing,
   - make `configure-xfce-wallpaper` also write `show-removable` consistent,
   - fcitx5 autostart/IM env verification.
5. After fix: build via workflow, re-download ISO, re-run the QEMU screenshot check
   (AGENTS.md quick verification section), `mise run ci`, commit/push.

## 6. Repo/workflow context (from AGENTS.md + BUILD_NOTES.md)

- Primary workflow: `trixie-xfce-toolbox-amd64.yml` (manual dispatch). Variants: standard (skips 05-apps —
  no WARP), ultra (all). Custom modules: `linux-live/scripts/07-customs/packages.list`.
- CI cleanup in `build-minios.yml` has a HISTORY of destructive deletes (fonts/icons/themes/.desktop) —
  suspect #1 when files go missing after a workflow change.
- rootcopy dirs are copied into chroot during module install (before package postinst runs).
- `minioslib` = core build functions; module order 00→10; `mise run ci` before claiming done.
