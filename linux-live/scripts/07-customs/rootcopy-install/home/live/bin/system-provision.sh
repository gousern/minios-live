#!/usr/bin/env bash
# repo=dotfiles
# filename=system-provision.sh
# ============================================================
#  system-provision.sh — MiniOS Debian 13 Edition
#
#  Self-healing dependency installer with fallback chains.
#  Every step reports and continues — no single point of failure.
#
#  Target: MiniOS 5.x (Debian 13 Trixie) + XFCE
# ============================================================

sudo timedatectl
sudo timedatectl set-ntp true

# No set -e — we want every step to run and report.
set -uo pipefail

# ---------- sudo and real user ----------
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
  REAL_USER="$USER"
  REAL_HOME="$HOME"
else
  SUDO=""
  if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  else
    REAL_USER="root"
    REAL_HOME="/root"
  fi
fi

# ---------- helpers ----------
step() {
  echo
  echo "============================================================"
  echo " ==> $*"
  echo "============================================================"
}

warn() { echo "WARNING: $*" >&2; }
fail() { echo "FAILED: $*" >&2; }

# Append a block to a file exactly once, keyed by a marker line.
# Usage: append_once <file> <marker> <content>
append_once() {
  local file="$1" marker="$2" content="$3"
  [[ -f "$file" ]] || touch "$file" || {
    warn "cannot create $file"
    return 1
  }
  if grep -qF "$marker" "$file"; then
    echo "    already present: $marker"
    return 0
  fi
  {
    printf '\n%s\n' "$marker"
    printf '%s\n' "$content"
  } >>"$file"
  echo "    appended: $marker"
}

# ---------- apt check ----------
if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: This script requires Debian/Ubuntu apt-get." >&2
  exit 1
fi

# ---------- OS detection ----------
# shellcheck disable=SC1091 # distro file; ID/CODENAME have fallbacks below
source /etc/os-release
OS_ID="${ID:-unknown}"
CODENAME="${VERSION_CODENAME:-trixie}"

echo "Detected: ${OS_ID} ${CODENAME}"

# ============================================================
#  SWITCH APT SOURCES TO ALIYUN
# ============================================================
switch_to_aliyun() {
  step "Switching APT sources to Aliyun mirrors"

  local backup_suffix
  printf -v backup_suffix '.bak.%s' "$(date +%Y%m%d%H%M%S)"

  case "$OS_ID" in
    debian)
      local sources=(
        /etc/apt/sources.list
        /etc/apt/sources.list.d/debian.sources
      )

      for f in "${sources[@]}"; do
        if [[ -f "$f" ]]; then
          echo "    backing up $f"
          $SUDO cp "$f" "${f}${backup_suffix}" 2>/dev/null || true

          $SUDO sed -i \
            -e "s|deb.debian.org/debian-security|mirrors.aliyun.com/debian-security|g" \
            -e "s|security.debian.org/debian-security|mirrors.aliyun.com/debian-security|g" \
            -e "s|deb.debian.org/debian|mirrors.aliyun.com/debian|g" \
            -e "s|security.debian.org|mirrors.aliyun.com/debian-security|g" \
            -e "s|deb.debian.org|mirrors.aliyun.com/debian|g" \
            "$f" 2>/dev/null || true
        fi
      done

      if [[ ! -s /etc/apt/sources.list ]]; then
        echo "    writing fresh Aliyun sources.list"
        cat <<EOF | $SUDO tee /etc/apt/sources.list >/dev/null
deb https://mirrors.aliyun.com/debian/ ${CODENAME} main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian/ ${CODENAME}-updates main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian/ ${CODENAME}-backports main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian-security/ ${CODENAME}-security main contrib non-free non-free-firmware
EOF
      fi

      echo "    Aliyun Debian mirror configured"
      ;;

    *)
      warn "Unsupported distribution: ${OS_ID}. Skipping mirror switch."
      return 0
      ;;
  esac

  echo "    Running apt-get update..."
  $SUDO apt-get update 2>&1 || warn "apt-get update had errors"
}

switch_to_aliyun

# ============================================================
#  BASE PACKAGES
# ============================================================
BASE_PKGS=(
  gawk
  fontconfig
  fonts-noto-color-emoji
  git
  tree
  curl
  wget
  vim
  ca-certificates
  gnupg
  lsb-release
)

step "Installing base packages"
printf '    %s\n' "${BASE_PKGS[@]}"
$SUDO apt-get install -y "${BASE_PKGS[@]}" 2>&1 | tee /tmp/apt-base.log || warn "some base packages failed"

# ============================================================
#  KERNEL HEADERS — with self-healing
# ============================================================
step "Resolving kernel headers"

KVER="$(uname -r)"
KHEADERS="linux-headers-${KVER}"

RESOLVED_KHEADERS=""
if apt-cache show "${KHEADERS}" >/dev/null 2>&1; then
  RESOLVED_KHEADERS="${KHEADERS}"
  echo "    exact match: ${RESOLVED_KHEADERS}"
else
  warn "exact headers not found: ${KHEADERS}"

  FLAVOR=""
  case "${KVER}" in
    *-amd64) FLAVOR="amd64" ;;
    *) FLAVOR="" ;;
  esac

  if [[ -n "${FLAVOR}" ]] && apt-cache show "linux-headers-${FLAVOR}" >/dev/null 2>&1; then
    RESOLVED_KHEADERS="linux-headers-${FLAVOR}"
    echo "    using meta package: ${RESOLVED_KHEADERS}"
  else
    echo "    trying snapshot.debian.org fallback..."
    SNAPSHOT_DATE=$(date +%Y%m%dT%H%M%SZ)
    cat <<EOF | $SUDO tee /etc/apt/sources.list.d/debian-snapshot.list >/dev/null
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${SNAPSHOT_DATE} trixie main
EOF

    $SUDO apt-get -o Acquire::Check-Valid-Until=false update 2>/dev/null || true

    if apt-cache show "${KHEADERS}" >/dev/null 2>&1; then
      RESOLVED_KHEADERS="${KHEADERS}"
      echo "    found via snapshot: ${RESOLVED_KHEADERS}"
    fi

    $SUDO rm -f /etc/apt/sources.list.d/debian-snapshot.list
    $SUDO apt-get update 2>/dev/null || true
  fi
fi

if [[ -n "${RESOLVED_KHEADERS}" ]]; then
  step "Installing kernel headers: ${RESOLVED_KHEADERS}"
  $SUDO apt-get install -y "${RESOLVED_KHEADERS}" 2>&1 || warn "kernel headers install failed"
fi

# ============================================================
#  APFS — self-healing with FUSE fallback
# ============================================================
step "APFS support (kernel module with FUSE fallback)"

APFS_KERNEL_OK=0
APFS_FUSE_OK=0

if apt-cache show apfs-dkms >/dev/null 2>&1; then
  echo "    attempting apfs-dkms..."
  $SUDO apt-get install -y dkms apfs-dkms 2>&1 | tee /tmp/apt-apfs.log

  if $SUDO dkms autoinstall 2>/dev/null; then
    if $SUDO modprobe apfs 2>/dev/null; then
      APFS_KERNEL_OK=1
      echo "    APFS kernel module loaded successfully"
    fi
  fi

  if [[ "$APFS_KERNEL_OK" -eq 0 ]]; then
    warn "apfs-dkms failed to build/load (known issue with Debian 13)"
  fi
else
  echo "    apfs-dkms not available in repos"
fi

if [[ "$APFS_KERNEL_OK" -eq 1 ]]; then
  echo "    APFS status: kernel module (read-write)"
elif [[ "$APFS_FUSE_OK" -eq 1 ]]; then
  echo "    APFS status: FUSE (read-only)"
else
  warn "APFS status: not available. Manual install may be required."
fi

# ============================================================
#  MAIN PACKAGES
# ============================================================
step "Installing main packages"

XFCE_X11_PKGS=(
  xinput
  xfce4-genmon-plugin
  libnotify-bin
)

FCITX_PKGS=(
  fcitx5
  fcitx5-chewing
)

MEDIA_PKGS=(
  mpv
  mpv-mpris
  ffmpeg
  socat
  jq
  playerctl
)

AUDIO_BT_PKGS=(
  pamixer
)

ANDROID_PKGS=(
  adb
  openssh-client
)

ALL_PKGS=(
  "${XFCE_X11_PKGS[@]}"
  "${FCITX_PKGS[@]}"
  "${MEDIA_PKGS[@]}"
  "${AUDIO_BT_PKGS[@]}"
  "${ANDROID_PKGS[@]}"
)

printf '    %s\n' "${ALL_PKGS[@]}"

$SUDO apt-get install -y -m --no-install-recommends "${ALL_PKGS[@]}" 2>&1 | tee /tmp/apt-main.log

FAILED=$(grep -oP '^E: Unable to locate package \K.*' /tmp/apt-main.log 2>/dev/null | tr '\n' ' ')
if [[ -n "$FAILED" ]]; then
  warn "packages not found: ${FAILED}"
fi

# ============================================================
#  CLOUDFLARE WARP — with self-healing
# ============================================================
step "Cloudflare WARP"

$SUDO mkdir -p /usr/share/keyrings

if curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
  | $SUDO gpg --yes --dearmor \
    --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null; then
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${CODENAME} main" \
    | $SUDO tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null

  $SUDO apt-get update 2>/dev/null || true

  if $SUDO apt-get install -y cloudflare-warp 2>&1; then
    echo "    WARP installed"

    if ! systemctl is-active --quiet warp-svc 2>/dev/null; then
      echo "    starting warp-svc..."
      $SUDO systemctl start warp-svc 2>/dev/null \
        || $SUDO service warp-svc start 2>/dev/null \
        || {
          $SUDO /usr/bin/warp-svc &
          sleep 2
        } 2>/dev/null
    fi

    if pgrep -x warp-svc >/dev/null; then
      echo "    warp-svc is running"
    else
      warn "warp-svc not running. Try: sudo systemctl start warp-svc"
    fi
  else
    warn "cloudflare-warp install failed"
  fi
else
  warn "could not fetch WARP GPG key. Skipping WARP."
fi

# ============================================================
#  MISE
# ============================================================
step "mise (dev tool version manager)"

if ! command -v mise >/dev/null 2>&1 && [[ ! -x "$REAL_HOME/.local/bin/mise" ]]; then
  echo "    installing via curl..."
  if [[ "${EUID}" -eq 0 && "$REAL_USER" != "root" ]]; then
    su - "$REAL_USER" -c 'curl -fsSL https://mise.run | sh' 2>/dev/null || warn "mise install failed"
  else
    curl -fsSL https://mise.run | sh 2>/dev/null || warn "mise install failed"
  fi
  export PATH="$REAL_HOME/.local/bin:$PATH"
else
  echo "    mise already present"
fi

# Activate in .bashrc
# shellcheck disable=SC2016 # $HOME must expand at login, not now
append_once "$REAL_HOME/.bashrc" "# >>> mise >>>" \
  'eval "$(~/.local/bin/mise activate bash)"'

# ============================================================
#  TERMUX HELPER FUNCTION
# ============================================================
step "Termux helper function"

append_once "$REAL_HOME/.bashrc" "# >>> termux >>>" \
  'termux() {
  adb shell -tt run-as com.termux \
    files/usr/bin/env \
      -C /data/user/0/com.termux/files/home \
      LD_PRELOAD=/data/data/com.termux/files/usr/lib/libtermux-exec.so \
      HOME=/data/user/0/com.termux/files/home \
      /data/data/com.termux/files/usr/bin/bash -li
}'

# ============================================================
#  MOTD
# ============================================================
step "MOTD"

install_motd() {
  local motd="$REAL_HOME/bin/motd"
  local bashrc="$REAL_HOME/.bashrc"
  local marker="# >>> custom motd >>>"

  if [[ ! -f "$motd" ]]; then
    warn "MOTD file not found: $motd"
    return 1
  fi

  if [[ ! -r "$motd" ]]; then
    warn "MOTD file is not readable: $motd"
    return 1
  fi

  # shellcheck disable=SC2016 # $HOME must expand when .bashrc runs, not now
  append_once "$bashrc" "$marker" 'if [[ -x "$HOME/bin/motd" ]]; then
    "$HOME/bin/motd"
fi
# <<< custom motd <<<'
}

install_motd

# ============================================================
#  FINAL STEPS
# ============================================================
step "macOS-style keyboard shortcuts"

# Applies xmodmap + xfwm4 Cmd+Tab + Firefox accel pref + terminal accels
# via the shared entry point. Failures only warn — provisioning continues.
PROVISION_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KBD_SCRIPT=""
for candidate in \
  "$PROVISION_DIR/macos_style_keyboard.sh" \
  "$REAL_HOME/git/dotfiles/macos_style_keyboard.sh" \
  "$REAL_HOME/bin/macos_style_keyboard.sh"; do
  if [[ -f "$candidate" ]]; then
    KBD_SCRIPT="$candidate"
    break
  fi
done

if [[ -z "$KBD_SCRIPT" ]]; then
  warn "macos_style_keyboard.sh not found (checked script dir, ~/git/dotfiles, ~/bin)"
  warn "  apply macOS shortcuts later with: ~/git/dotfiles/macos_style_keyboard.sh --yes"
else
  echo "    applying: bash $KBD_SCRIPT --yes"
  if [[ "${EUID}" -eq 0 && "$REAL_USER" != "root" ]]; then
    env_str="DISPLAY=${DISPLAY:-} DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}"
    if [[ -n "${XAUTHORITY:-}" ]]; then
      env_str+=" XAUTHORITY=$XAUTHORITY"
    fi
    su - "$REAL_USER" -c "$env_str bash \"$KBD_SCRIPT\" --yes" \
      || warn "macOS-style shortcuts step had errors (re-run: bash $KBD_SCRIPT --yes)"
  else
    bash "$KBD_SCRIPT" --yes \
      || warn "macOS-style shortcuts step had errors (re-run: bash $KBD_SCRIPT --yes)"
  fi
fi

step "Refreshing font cache"
fc-cache -fv >/dev/null 2>&1 || true

step "Final verification"

MISSING=()
for cmd in \
  fcitx5 fcitx5-remote \
  fc-list fc-cache \
  git curl wget \
  xkbcomp setxkbmap xmodmap xev \
  xrandr xset xdotool xinput \
  desktop-file-validate \
  mpv socat jq playerctl notify-send \
  adb bluetoothctl \
  pactl amixer pamixer \
  ssh ssh-keygen ssh-copy-id ssh-keyscan \
  base64 pgrep pkill \
  warp-cli mise \
  fsapfsmount apfs-fuse; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '    ✔ %s\n' "$cmd"
  else
    printf '    ✘ %s (missing)\n' "$cmd"
    MISSING+=("$cmd")
  fi
done

echo
if ((${#MISSING[@]})); then
  warn "some commands are missing:"
  printf '    %s\n' "${MISSING[@]}"
  echo "    These may require manual installation."
else
  echo "All checked commands are available."
fi

echo
echo "============================================================"
echo " Done."
echo "============================================================"
echo
echo "Next steps:"
echo "  1. Put scripts in ~/bin and chmod +x ~/bin/*.sh"
echo "  2. Termux: install Termux:API, Termux:Widget, then 'pkg install openssh termux-api'"
echo "  3. WARP: warp-cli register  (if daemon is running)"
echo "  4. Reload shell: source ~/.bashrc"
