#!/usr/bin/env bash
# repo=dotfiles
# filename=screen.sh
# ============================================================================
#  install-resolution.sh
#  Force display to 1280x800 @ 60 Hz and persist via autostart.
# ============================================================================

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
TARGET_W=1280
TARGET_H=800
TARGET_RATE=60
TARGET_MODE="${TARGET_W}x${TARGET_H}"

HOME_DIR="${HOME:-/home/live}"
AUTOSTART_DIR="$HOME_DIR/.config/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/set-resolution.desktop"
HELPER_SCRIPT="$HOME_DIR/.local/bin/set-resolution.sh"
LOG_FILE="$HOME_DIR/.local/share/set-resolution.log"

VERBOSE="${VERBOSE:-false}"
AUTO_YES="${AUTO_YES:-false}"

# ─── Colors & Symbols ───────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
  RED=$'\033[1;31m'
  GRN=$'\033[1;32m'
  YLW=$'\033[1;33m'
  BLU=$'\033[1;34m'
  MAG=$'\033[1;35m'
  CYN=$'\033[1;36m'
  WHT=$'\033[1;37m'
else
  BOLD=""
  DIM=""
  RESET=""
  RED=""
  GRN=""
  YLW=""
  BLU=""
  MAG=""
  CYN=""
  WHT=""
fi

SYM_OK="✔"
SYM_NO="✘"
SYM_WARN="⚠"
SYM_INFO="➜"
SYM_BULLET="•"
SYM_STEP="▸"
SYM_FIX="⚙"

STEP_NUM=0
TOTAL_STEPS=5

# ─── Pretty Printing ────────────────────────────────────────────────────────
hr() { printf '%s\n' "${DIM}────────────────────────────────────────────────────────────${RESET}"; }
hr_double() { printf '%s\n' "${BLU}════════════════════════════════════════════════════════════${RESET}"; }

banner() {
  local title="$1"
  STEP_NUM=$((STEP_NUM + 1))
  printf '\n'
  hr_double
  printf '  %s[%d/%d]%s  %s%s%s\n' "$MAG" "$STEP_NUM" "$TOTAL_STEPS" "$RESET" "$BOLD$WHT" "$title" "$RESET"
  hr_double
}

info() { printf '   %s%s%s %s\n' "$CYN" "$SYM_INFO" "$RESET" "$*"; }
fix() { printf '   %s%s%s %s\n' "$CYN" "$SYM_FIX" "$RESET" "$*"; }
ok() { printf '   %s%s%s %s\n' "$GRN" "$SYM_OK" "$RESET" "$*"; }
warn() { printf '   %s%s%s %s\n' "$YLW" "$SYM_WARN" "$RESET" "$*"; }
fail() { printf '   %s%s%s %s\n' "$RED" "$SYM_NO" "$RESET" "$*"; }
bullet() { printf '     %s%s%s %s\n' "$DIM" "$SYM_BULLET" "$RESET" "$*"; }
kv() { printf '     %s%-16s%s %s\n' "$DIM" "$1" "$RESET" "$2"; }

die() {
  printf '\n   %s%s FATAL:%s %s\n\n' "$RED" "$SYM_NO" "$RESET" "$*" >&2
  exit 1
}

ask_yes() {
  local prompt="$1"
  if [[ "$AUTO_YES" == "true" ]]; then
    printf '   %s?%s %s %s[auto-yes]%s\n' "$YLW" "$RESET" "$prompt" "$DIM" "$RESET"
    return 0
  fi
  local ans
  read -r -p "$(printf '   %s?%s %s [y/N] ' "$YLW" "$RESET" "$prompt")" ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# ─── Package Manager Detection ──────────────────────────────────────────────
detect_pkg_mgr() {
  if command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v pacman &>/dev/null; then
    echo "pacman"
  elif command -v zypper &>/dev/null; then
    echo "zypper"
  elif command -v apk &>/dev/null; then
    echo "apk"
  else
    echo "unknown"
  fi
}

pkg_for_tool() {
  local tool="$1" mgr="$2"
  case "$tool:$mgr" in
    xrandr:apt) echo "x11-xserver-utils" ;;
    xrandr:dnf) echo "xrandr" ;;
    xrandr:pacman) echo "xorg-xrandr" ;;
    xrandr:zypper) echo "xrandr" ;;
    xrandr:apk) echo "xrandr" ;;
    *) echo "" ;;
  esac
}

install_pkg() {
  local mgr="$1" pkg="$2"
  local sudo=""
  [[ "$(id -u)" -ne 0 ]] && sudo="sudo"
  case "$mgr" in
    apt) $sudo apt-get update -qq && $sudo apt-get install -y "$pkg" ;;
    dnf) $sudo dnf install -y "$pkg" ;;
    pacman) $sudo pacman -S --noconfirm "$pkg" ;;
    zypper) $sudo zypper install -y "$pkg" ;;
    apk) $sudo apk add "$pkg" ;;
    *) return 1 ;;
  esac
}

ensure_tool() {
  local tool="$1"
  if command -v "$tool" &>/dev/null; then
    ok "$tool  ${DIM}($(command -v "$tool"))${RESET}"
    return 0
  fi
  warn "$tool  ${DIM}— not found${RESET}"
  local mgr
  mgr="$(detect_pkg_mgr)"
  local pkg
  pkg="$(pkg_for_tool "$tool" "$mgr")"
  if [[ -z "$pkg" || "$mgr" == "unknown" ]]; then
    fail "Don't know how to install $tool on this system."
    return 1
  fi
  printf '\n'
  info "Package manager detected: ${BOLD}$mgr${RESET}"
  info "Package to install:      ${BOLD}$pkg${RESET}"
  printf '\n'
  if ! ask_yes "Install '$pkg' now?"; then
    fail "Skipped. $tool is required."
    return 1
  fi
  printf '\n'
  info "Running: ${DIM}$mgr install $pkg${RESET}"
  hr
  if install_pkg "$mgr" "$pkg"; then
    hr
    command -v "$tool" &>/dev/null && {
      ok "$tool installed successfully"
      return 0
    }
    fail "$tool still not found after install"
    return 1
  fi
  hr
  fail "Installation of '$pkg' failed"
  return 1
}

# ─── Detect first connected output ──────────────────────────────────────────
detect_output() {
  xrandr --query 2>/dev/null \
    | awk '/ connected/ {print $1; exit}'
}

# ─── Check whether a mode exists on the given output ────────────────────────
mode_available() {
  local output="$1" mode="$2"
  xrandr --query 2>/dev/null \
    | awk -v out="$output" -v m="$mode" '
            $1 == out      { in_block = 1; next }
            in_block && $1 == "" { in_block = 0 }
            in_block && /^[[:space:]]/ {
                for (i = 1; i <= NF; i++) if ($i == m) { print "yes"; exit }
            }
        ' | grep -q yes
}

# ─── Apply resolution to a given output (idempotent) ────────────────────────
apply_resolution() {
  local output="$1"
  local current
  current=$(xrandr --query 2>/dev/null | awk -v out="$output" '$1 == out && $2 == "connected" { for (i=1;i<=NF;i++) if ($i == "current") print $(i+1)"x"$(i+3); exit }')

  if [[ "$current" == "$TARGET_MODE" ]]; then
    ok "Already at ${TARGET_MODE} on ${output}"
    return 0
  fi

  if ! mode_available "$output" "$TARGET_MODE"; then
    warn "Mode ${TARGET_MODE} not advertised by ${output}"
    info "Available modes for ${output}:"
    xrandr --query | awk -v out="$output" '
            $1 == out { in_block = 1; next }
            in_block && /^[[:space:]]/ { print "       " $1 }
        ' | head -n 10
    return 1
  fi

  if xrandr --output "$output" --mode "$TARGET_MODE" --rate "$TARGET_RATE" 2>/dev/null; then
    ok "Set ${output} → ${TARGET_MODE}@${TARGET_RATE}Hz"
    return 0
  fi
  if xrandr --output "$output" --mode "$TARGET_MODE" 2>/dev/null; then
    warn "Rate ${TARGET_RATE}Hz refused; set ${output} → ${TARGET_MODE} at default rate"
    return 0
  fi
  fail "Could not set ${output} → ${TARGET_MODE}"
  return 1
}

# ============================================================================
#  MAIN
# ============================================================================

printf '\n'
hr_double
printf '  %s%s  Display resolution → %s  %s\n' "$BOLD$MAG" "$SYM_STEP" "$TARGET_MODE" "$RESET"
printf '  %sAutostart: %s%s\n' "$DIM" "$DESKTOP_FILE" "$RESET"
hr_double

# ─── STEP 1: Dependencies ───────────────────────────────────────────────────
banner "Checking dependencies"

REQUIRED_TOOLS=(xrandr)
MISSING=()
printf '   %sScanning for required tools…%s\n\n' "$DIM" "$RESET"
for t in "${REQUIRED_TOOLS[@]}"; do
  command -v "$t" &>/dev/null || MISSING+=("$t")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  for t in "${REQUIRED_TOOLS[@]}"; do
    ok "$t  ${DIM}($(command -v "$t"))${RESET}"
  done
  printf '\n   %s%s All dependencies present.%s\n' "$GRN" "$SYM_OK" "$RESET"
else
  printf '   %s%d tool(s) missing:%s %s\n\n' "$YLW" "${#MISSING[@]}" "$RESET" "${MISSING[*]}"
  for t in "${MISSING[@]}"; do
    ensure_tool "$t" || die "Cannot proceed without '$t'."
    printf '\n'
  done
fi

# ─── STEP 2: Detect output & apply resolution now ───────────────────────────
banner "Applying resolution to active display"

OUTPUT="$(detect_output || true)"
if [[ -z "$OUTPUT" ]]; then
  die "No connected display found. Is X running on \$DISPLAY=${DISPLAY:-unset}?"
fi

kv "Output" "$OUTPUT"
kv "Target" "${TARGET_MODE}@${TARGET_RATE}Hz"
kv "Display" "${DISPLAY:-unset}"
printf '\n'

apply_resolution "$OUTPUT" || warn "Live apply failed — autostart will retry at next login"

# ─── STEP 3: Install the helper script ──────────────────────────────────────
banner "Installing helper script"

HELPER_DIR="$(dirname "$HELPER_SCRIPT")"
LOG_DIR="$(dirname "$LOG_FILE")"

for d in "$HELPER_DIR" "$LOG_DIR"; do
  if [[ -d "$d" ]]; then
    ok "Directory exists: $d"
  else
    mkdir -p "$d"
    ok "Created: $d"
  fi
done

kv "Helper" "$HELPER_SCRIPT"
kv "Log" "$LOG_FILE"
printf '\n'

cat >"$HELPER_SCRIPT" <<HELPER_EOF
#!/usr/bin/env bash
# Auto-generated by install-resolution.sh
# Applies ${TARGET_MODE}@${TARGET_RATE}Hz to the first connected output.
# Waits for the display server to settle, retries a few times, logs results.

set -u
LOG="${LOG_FILE}"
W=${TARGET_W}
H=${TARGET_H}
R=${TARGET_RATE}
MODE="\${W}x\${H}"

mkdir -p "\$(dirname "\$LOG")"
log() { printf '[%s] %s\n' "\$(date '+%F %T')" "\$*" >> "\$LOG"; }

log "=== set-resolution start (DISPLAY=\${DISPLAY:-unset}) ==="

# Wait up to ~10s for the display to become queryable
for i in \$(seq 1 20); do
    xrandr --query >/dev/null 2>&1 && break
    sleep 0.5
done

OUTPUT=\$(xrandr --query 2>/dev/null | awk '/ connected/ {print \$1; exit}')
if [[ -z "\$OUTPUT" ]]; then
    log "ERROR: no connected output found"
    exit 1
fi
log "Target output: \$OUTPUT"

CURRENT=\$(xrandr --query 2>/dev/null | awk -v out="\$OUTPUT" '\$1 == out && \$2 == "connected" { for (i=1;i<=NF;i++) if (\$i == "current") print \$(i+1)"x"\$(i+3); exit }')
if [[ "\$CURRENT" == "\$MODE" ]]; then
    log "Already at \$MODE — nothing to do"
    exit 0
fi

# Verify the mode exists
if ! xrandr --query 2>/dev/null | awk -v out="\$OUTPUT" -v m="\$MODE" '
        \$1 == out { in_block = 1; next }
        in_block && /^[[:space:]]/ { for (i=1;i<=NF;i++) if (\$i == m) { print "yes"; exit } }
    ' | grep -q yes; then
    log "ERROR: mode \$MODE not advertised by \$OUTPUT"
    exit 1
fi

if xrandr --output "\$OUTPUT" --mode "\$MODE" --rate "\$R" >>"\$LOG" 2>&1; then
    log "SUCCESS: \$OUTPUT → \$MODE@\${R}Hz"
    exit 0
fi
if xrandr --output "\$OUTPUT" --mode "\$MODE" >>"\$LOG" 2>&1; then
    log "SUCCESS (fallback rate): \$OUTPUT → \$MODE"
    exit 0
fi

log "ERROR: xrandr failed to set \$MODE on \$OUTPUT"
exit 1
HELPER_EOF

chmod +x "$HELPER_SCRIPT"
ok "Helper written and marked executable"

# ─── STEP 4: Install the autostart entry ────────────────────────────────────
banner "Installing autostart entry"

if [[ -d "$AUTOSTART_DIR" ]]; then
  ok "Autostart directory exists"
else
  mkdir -p "$AUTOSTART_DIR"
  ok "Created $AUTOSTART_DIR"
fi

kv "Desktop file" "$DESKTOP_FILE"
printf '\n'

if [[ -f "$DESKTOP_FILE" ]]; then
  BACKUP="${DESKTOP_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$DESKTOP_FILE" "$BACKUP"
  ok "Backed up existing entry to $(basename "$BACKUP")"
fi

cat >"$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Set Resolution
Comment=Set display to ${TARGET_MODE}@${TARGET_RATE}Hz on login
Exec=${HELPER_SCRIPT}
Terminal=false
StartupNotify=false
OnlyShowIn=XFCE;GNOME;KDE;LXDE;LXQt;MATE;Cinnamon;Unity;
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
DESKTOP_EOF

chmod 644 "$DESKTOP_FILE"
ok "Autostart .desktop written"

if command -v desktop-file-validate &>/dev/null; then
  if desktop-file-validate "$DESKTOP_FILE" 2>/dev/null; then
    ok "desktop-file-validate: OK"
  else
    warn "desktop-file-validate reported issues:"
    desktop-file-validate "$DESKTOP_FILE" 2>&1 | sed 's/^/     /' || true
  fi
else
  info "desktop-file-validate not installed — skipping strict validation"
fi

# ─── STEP 5: Verification ───────────────────────────────────────────────────
banner "Verifying installation"

printf '   %sCurrent state:%s\n\n' "$BOLD" "$RESET"

LIVE="$(xrandr --query 2>/dev/null | awk -v out="$OUTPUT" '$1 == out && $2 == "connected" { for (i=1;i<=NF;i++) if ($i == "current") print $(i+1)"x"$(i+3); exit }')"
if [[ "$LIVE" == "$TARGET_MODE" ]]; then
  ok "Live resolution: ${LIVE} on ${OUTPUT}"
else
  warn "Live resolution: ${LIVE:-unknown} (target: ${TARGET_MODE})"
fi

if [[ -x "$HELPER_SCRIPT" ]]; then
  ok "Helper executable: $HELPER_SCRIPT"
else
  fail "Helper missing or not executable"
fi

if [[ -f "$DESKTOP_FILE" ]]; then
  ok "Autostart entry present: $DESKTOP_FILE"
else
  fail "Autostart entry missing"
fi

EXEC_LINE="$(awk -F= '/^Exec=/{sub(/^Exec=/,""); print; exit}' "$DESKTOP_FILE" 2>/dev/null || true)"
if [[ "$EXEC_LINE" == "$HELPER_SCRIPT" ]]; then
  ok "Exec points to helper: $EXEC_LINE"
else
  warn "Exec line mismatch: '$EXEC_LINE'"
fi

printf '\n   %sAutostart entries in %s:%s\n\n' "$BOLD" "$AUTOSTART_DIR" "$RESET"
find "$AUTOSTART_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | sort | sed 's/^/     /' || info "None"

if [[ -f "$LOG_FILE" ]]; then
  printf '\n   %sLast log lines (%s):%s\n\n' "$BOLD" "$LOG_FILE" "$RESET"
  tail -n 10 "$LOG_FILE" | sed 's/^/     /'
fi

# ─── Done ───────────────────────────────────────────────────────────────────
printf '\n'
hr_double
printf '  %s%s  Resolution configured and persisted.%s\n' "$GRN" "$SYM_OK" "$RESET"
hr_double

printf '\n   %sQuick reference:%s\n\n' "$BOLD" "$RESET"
bullet "Helper:    $HELPER_SCRIPT"
bullet "Autostart: $DESKTOP_FILE"
bullet "Log:       $LOG_FILE"
printf '\n   %sTo test without logging out:%s\n\n' "$BOLD" "$RESET"
printf '     %s%s%s\n' "$CYN" "$HELPER_SCRIPT" "$RESET"
printf '\n   %sTo disable autostart:%s\n\n' "$BOLD" "$RESET"
printf '     %srm %s%s\n' "$CYN" "$DESKTOP_FILE" "$RESET"
printf '\n'
