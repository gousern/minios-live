#!/usr/bin/env bash
# repo=dotfiles
# filename=im.sh
# Verify Fcitx5 + Chewing and auto-generate a fix script if issues found
# Loops until all checks pass or MAX_ROUNDS reached
# Usage: bash im.sh

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
FIX_LINES=()
FIX_SCRIPT="/tmp/fix.sh"
MAX_ROUNDS=5

pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  PASS=$((PASS + 1))
}
fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  FAIL=$((FAIL + 1))
}
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "       $1"; }
add_fix() {
  # Usage: add_fix <label> <script>
  # label is short, single-line, no quotes; script may be multi-line
  FIX_LINES+=("$1"$'\t'"$2")
}

# ============================================
# Main check-and-fix loop
# ============================================
run_checks() {
  PASS=0
  FAIL=0
  FIX_LINES=()

  # ---------- 1. Packages ----------
  echo -e "${BLUE}--- 1. Packages ---${NC}"
  MISSING_PKGS=()
  for pkg in fcitx5 fcitx5-chewing fcitx5-config-qt fcitx5-frontend-gtk3 fcitx5-frontend-qt5 fonts-wqy-zenhei; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      pass "$pkg"
    else
      fail "$pkg missing"
      MISSING_PKGS+=("$pkg")
    fi
  done
  if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    add_fix "apt update" "sudo apt update"
    add_fix "install missing packages" "sudo apt install -y ${MISSING_PKGS[*]}"
  fi
  echo

  # ---------- 2. Binaries ----------
  echo -e "${BLUE}--- 2. Binaries ---${NC}"
  for bin in fcitx5 fcitx5-remote fcitx5-config-qt; do
    if command -v "$bin" >/dev/null 2>&1; then
      pass "$bin"
    else
      fail "$bin not found"
      add_fix "install fcitx5-config-qt" "sudo apt install -y fcitx5-config-qt"
    fi
  done
  echo

  # ---------- 3. Environment ----------
  echo -e "${BLUE}--- 3. Environment Variables ---${NC}"
  XPROFILE="$HOME/.xprofile"
  check_env() {
    local var="$1" expected="$2"
    local val="${!var:-}"
    if [ "$val" = "$expected" ]; then
      pass "$var=$val"
    else
      fail "$var=${val:-<empty>} (expected: $expected)"
      add_fix "ensure $var in .xprofile" \
        "touch \"$XPROFILE\"
grep -Fxq 'export $var=$expected' \"$XPROFILE\" || echo 'export $var=$expected' >> \"$XPROFILE\"
export $var=$expected"
    fi
  }
  check_env GTK_IM_MODULE fcitx
  check_env QT_IM_MODULE fcitx
  check_env XMODIFIERS "@im=fcitx"
  echo

  # ---------- 4. Runtime ----------
  echo -e "${BLUE}--- 4. Runtime ---${NC}"
  if pgrep -x fcitx5 >/dev/null 2>&1; then
    pass "fcitx5 running"
  else
    fail "fcitx5 not running"
    add_fix "start fcitx5" "fcitx5 -d --replace"
  fi
  echo

  # ---------- 5. Chewing engine ----------
  echo -e "${BLUE}--- 5. Chewing Engine ---${NC}"
  if find /usr/lib -name "*chewing*" 2>/dev/null | grep -q .; then
    pass "Chewing library present"
  else
    fail "Chewing library missing"
    add_fix "reinstall fcitx5-chewing" "sudo apt install --reinstall -y fcitx5-chewing"
  fi
  echo

  # ---------- 6. Profile ----------
  echo -e "${BLUE}--- 6. Fcitx5 Profile ---${NC}"
  PROFILE="$HOME/.config/fcitx5/profile"
  if [ -f "$PROFILE" ] && grep -qi "chewing" "$PROFILE"; then
    pass "Chewing in profile"
  else
    fail "Chewing not configured"
    add_fix "write fcitx5 profile" \
      "mkdir -p \"$(dirname "$PROFILE")\"
cat > \"$PROFILE\" <<'PROFILE_EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=chewing

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=chewing
Layout=

[GroupOrder]
0=Default
PROFILE_EOF"
    add_fix "reload fcitx5" "fcitx5-remote -r || fcitx5 -d --replace"
  fi
  echo

  # ---------- 7. Fonts ----------
  echo -e "${BLUE}--- 7. Chinese Fonts ---${NC}"
  if fc-list :lang=zh 2>/dev/null | grep -q .; then
    pass "Chinese fonts available"
  else
    fail "No Chinese fonts"
    add_fix "install Chinese fonts" "sudo apt install -y fonts-wqy-zenhei fonts-wqy-microhei"
    add_fix "refresh font cache" "fc-cache -fv"
  fi
  echo

  # ---------- SUMMARY ----------
  echo "==============================================="
  echo -e " ${BLUE}SUMMARY${NC}"
  echo "==============================================="
  echo -e " Passed: ${GREEN}$PASS${NC}"
  echo -e " Failed: ${RED}$FAIL${NC}"
  echo
}

# ============================================
# Generate and run fix script
# ============================================
apply_fixes() {
  echo -e "${YELLOW}Generating fix script: $FIX_SCRIPT${NC}"

  {
    echo "#!/usr/bin/env bash"
    echo "# Auto-generated fix script for Fcitx5 + Chewing"
    echo "# Generated on: $(date)"
    echo "# Run with: bash $FIX_SCRIPT"
    echo
    echo "set -u"
    echo "echo '=== Applying Fcitx5 + Chewing fixes ==='"
    echo
    for entry in "${FIX_LINES[@]}"; do
      label="${entry%%$'\t'*}"
      script="${entry#*$'\t'}"
      printf '%s\n' "$script"
      printf 'echo %q\n' "[done] $label"
      echo
    done
    echo "echo '=== All fixes applied ==='"
    echo "echo 'Please log out and log back in, then press Ctrl+Space.'"
  } >"$FIX_SCRIPT"

  chmod +x "$FIX_SCRIPT"
  echo -e "${GREEN}✔ Fix script created:${NC} $FIX_SCRIPT"
  echo
  bash "$FIX_SCRIPT"
  echo
}

# ============================================
# Load user environment
# ============================================
if [ -f "$HOME/.xprofile" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.xprofile"
fi

echo "==============================================="
echo " Fcitx5 + Chewing Verify & Fix Generator"
echo "==============================================="
echo

# ============================================
# Loop: check → fix → re-check until clean
# ============================================
for round in $(seq 1 "$MAX_ROUNDS"); do
  echo -e "${YELLOW}=== Round $round/$MAX_ROUNDS ===${NC}"
  echo

  run_checks

  if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}✔ All checks passed!${NC}"
    echo "  Use Ctrl+Space to switch input methods."
    exit 0
  fi

  echo -e "${YELLOW}Found $FAIL issue(s). Applying fixes...${NC}"
  echo
  apply_fixes

  # Reload environment for next round
  if [ -f "$HOME/.xprofile" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.xprofile"
  fi
done

echo -e "${RED}✘ Still $FAIL issue(s) after $MAX_ROUNDS rounds. Please fix manually.${NC}"
exit 1
