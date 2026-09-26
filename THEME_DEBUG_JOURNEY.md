# THEME_DEBUG_JOURNEY.md — chronological debug log

> Narrative of how "MiniOS default theme missing" was found and fixed.
> Companion: `THEME_DEBUG.md` (facts/state), `BUILD_NOTES.md` (build lessons).
> Dates: 2026-09-26/27 (UTC+8 / UTC), host: Debian 13, repo: `gousern/minios-live`.

## Phase 0 — Report

- Built ISO: `minios-trixie-xfce-toolbox-amd64-5.2.0-custom.iso` (release `v5.2.0-custom`).
- WARP/apfs/broadcom now install fine (07-customs OK), but **MiniOS default theme missing in XFCE**.
- Later added: **`mise` not working in the booted ISO** and **boot resolution not 1280×800**.

## Phase 1 — Static inspection of the built ISO (dead ends first)

1. Mounted ISO at `/mnt/iso`; found aufs per-module squashfs under `/minios/*.sb`
   (`00-core … 07-customs`) instead of one `filesystem.squashfs`.
2. Extracted modules (`sudo unsquashfs -d /tmp/sqNNx …`) and hunted for missing theme files:
   - `minios6-artwork` installed; backgrounds incl. `minios6-toolbox.jpg` present in `04`.
   - skel xfconf present: `xsettings.xml` = **Greybird** + **elementary-minios-dark**,
     `xfce4-desktop.xml` rewritten by `configure-xfce-wallpaper` postinst with monitor list
     + `last-image=/usr/share/backgrounds/minios6-toolbox.jpg`.
3. **Whiteout trap**: first check used `unsquashfs -l` — it does NOT show whiteout char-devs.
   Re-ran with `unsquashfs -ll | grep -E "^[cb]"` → **no theme-related whiteouts** anywhere
   (only `05`'s expected `wl.ko` whiteout). Files were fine → "missing file" theory died.

## Phase 2 — Live QEMU debugging (hardest, most lessons)

Built rig `/tmp/qshot/`: `launch.sh` (pid 5950), monitor via `socat unix-connect:mon.sock`,
`screendump` + PIL for screenshots, VNC `:1`.

What worked / what didn't (don't re-learn these):

| Channel | Result |
|---|---|
| QEMU monitor `sendkey` | ✅ works (`alt-f2` opened Application Finder). `super` key name = **invalid** here |
| QEMU monitor `mouse_move`/`mouse_button` | ❌ no effect on guest cursor |
| VNC input (`vncinput.py`, pure-python RFB) | ❌ QEMU VNC offers security None then returns **"Authentication failed"** |
| SSH (hotplugged e1000 + `hostfwd :2222`) | ❌ host port accepts, no guest banner (NIC/sshd never reachable) |
| VT switch `ctrl-alt-f1/f3` | ❌ blocked by X/logind; `ctrl-alt-f2` did switch once |
| Console passwords | from login banner: **`live: evil`, `root: toor`** |
| `gh` CLI | ✅ works (needs `-R gousern/minios-live` — defaults to UPSTREAM, see Phase 6) |

Live observations (symptoms):
- **Black wallpaper from first frame**; File System + Floppy icons visible even though skel XML says
  `show-filesystem=false` / `show-removable=false` → **skel xfce4-desktop config NOT applied**.
- GTK text input eaten (`sendkey x` into focused appfinder entry → nothing) — suspected fcitx IM.
- Panel clock froze / session wedged after minutes; multiple session states observed
  (lightdm restart loop). xdg autostart/`minios-virtual-resolution` still worked system-wide
  → guest ended at 1280×800 in QEMU, but skel `set-resolution.desktop` never ran.

Conclusion of Phase 2: the whole `~/.config/xfce4` tree is missing at runtime, while
`/etc/skel` in the image is correct → problem is in **boot-time home population**.

## Phase 3 — Ground truth: official 5.1.1 ISO

- Downloaded `minios-trixie-xfce-toolbox-amd64-5.1.1.iso` from `minios-linux/minios-live`
  (gh release download; first attempt stalled at 1.2 GB → restart worked).
- **sha256 verified** vs release asset: `ca4f7d25…9979` ✅.
- Diff vs our ISO: **official `05-apps` has NO `/home/live`**; ours does
  (`/home/live/bin/{im.sh,screen.sh,system-provision.sh,macos_style_firefox_fonts.sh}` — fork's dotfiles).
- Official also has **no 07-customs** at all (00–06 only).

## Phase 4 — Root cause (source-level proof)

Chain for the theme/wallpaper/resolution symptoms:

1. `05-apps/rootcopy-install/home/live/…` **bakes `/home/live/` into the image**.
2. Boot: `minios-live-config` `components/0030-user-setup` → Debian `user-setup-apply` → `adduser`.
3. `adduser` `create_homedir` (`/usr/sbin/adduser` lines 1070–1112): home exists →
   *"The home directory already exists. Not touching this directory"* →
   **`/etc/skel` copy only happens in the create-home branch → skipped**.
4. Result: live user gets **no** `~/.config/xfce4` (default theme/black wallpaper/default icons),
   **no** `~/.config/autostart/set-resolution.desktop` (resolution fix never runs),
   **no** `.xprofile`/fcitx5 profile, **no** `.bashrc`.
5. Component then only `mkdir`s XDG dirs + `chown -R live:live` (which conveniently fixes
   ownership of anything we seed at build time).

Chain for `mise`:

1. `07-customs/install` ran `curl https://mise.run | bash` **as root in the chroot** →
   binary at `/root/.local/bin/mise` (146 MB — verified inside the 07 module) → invisible to `live`.
2. `mise.run` installer supports **`MISE_INSTALL_PATH`** (read from installer source:
   `install_path="${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}"`).
3. 05's skel `.bashrc` line `eval "$(~/.local/bin/mise activate bash)"` would also error once
   the home is seeded (it never did before, because `.bashrc` itself was missing!).
4. Host-side, `mise run ci` was broken too: shim error `No version is set for shim: jaq`
   → fixed with `mise use -g jaq@3.1.1`. (Note: repo has **no `mise.toml`**, so
   `mise run ci/lint` do not exist despite AGENTS.md — tasks undefined.)

## Phase 5 — Fix + validation

Commit `6488c1c0` (pushed):

1. `linux-live/scripts/07-customs/install`:
   - mise → `curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh` (system-wide).
   - **End of module (must stay last)**: `cp -a /etc/skel/. /home/live/` — seeds the baked home
     with all skel configs; boot chown handles ownership.
2. `linux-live/scripts/05-apps/rootcopy-install/etc/skel/.bashrc`:
   guarded activate (use `~/.local/bin/mise` if executable, else PATH; silent when absent).
3. `THEME_DEBUG.md` updated with root cause.

Validation done: `shellcheck -S warning` rc=0; `bash -n` both files; guard logic tested with and
without mise; skel completeness re-verified in image (Greybird, elementary-minios-dark,
`minios6-toolbox.jpg`, `set-resolution.desktop`). shfmt diffs are **pre-existing**
(HEAD fails too — file uses 4-space indent; left untouched per "only touch what must be touched").

## Phase 6 — Release & rebuild status

- Tag **`v5.2.1-custom`** pushed; release created:
  `https://github.com/gousern/minios-live/releases/tag/v5.2.1-custom`
  (release must exist BEFORE the workflow's `gh release upload` step runs).
- First dispatch attempt **failed: HTTP 403 on `minios-linux/minios-live`** — `gh workflow run`
  resolved the workflow in the **upstream** repo. Fix: always pass
  **`-R gousern/minios-live`** for this repo's workflows/runs/releases.
- Successful dispatch: run **`36272402288`**
  (`https://github.com/gousern/minios-live/actions/runs/36272402288`), started 2026-09-26 21:17 UTC;
  previous run took ~29 min.

## Phase 7 — Post-build verification checklist (TODO when run completes)

1. `gh run view 36272402288 -R gousern/minios-live` → success; release asset uploaded.
2. Download new ISO + verify (workflow emits `.sha256`).
3. Mount → assert **no** `home/live`-only-baked problem: `/home/live` now contains
   `.config/xfce4/...` seeded from skel (check `xsettings.xml`, `xfce4-desktop.xml`,
   `.config/autostart/set-resolution.desktop`), and `/usr/local/bin/mise` exists,
   `/root/.local/bin/mise` does **not**.
4. Boot in `/tmp/qshot` rig → screenshots must show MiniOS wallpaper + themed desktop;
   resolution 1280×800; in guest: `mise --version` works for user `live`.

## Lessons (quick list)

- `unsquashfs -l` hides whiteouts → always `-ll` + `grep -E "^[cb]"`.
- Baked home dir in a live image = silent skel-skip (`adduser` behavior).
- `curl | sh` installers run as root land in `/root` — pin `MISE_INSTALL_PATH`.
- QEMU: monitor sendkey ✅ / mouse ❌ / VNC auth "failed" / SSH unreachable / VT switch mostly blocked.
- `gh` defaults to UPSTREAM repo when local remote/`-R` ambiguous → always `-R gousern/minios-live`.
- Workflow builds from **tag input** (`git clone --branch $tag`) and uploads to an **existing release**.
- Guest console creds: `live: evil`, `root: toor`.
