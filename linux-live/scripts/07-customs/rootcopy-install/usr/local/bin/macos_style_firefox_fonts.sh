#!/usr/bin/env bash
# =============================================================================
#  setup-pingfang-tc-firefox.sh
# -----------------------------------------------------------------------------
#  Install PingFang Relaxed TC from ACT-02/PingFang-Relaxed into
#  ~/.local/share/fonts/PingFang, register it with Fontconfig, and configure
#  Firefox (on XFCE) to use it for Traditional Chinese.
#
#  Fixed: check_font() and verify() no longer use "grep -q" inside a pipeline
#  under "set -o pipefail". grep -q exits on the first match, closing the pipe,
#  which makes the upstream fc-list die with SIGPIPE (141). pipefail then
#  reports the pipeline as failed even though grep matched. The result was
#  that the script thought the font was missing on every run.
# =============================================================================

set -euo pipefail

# ----- CONFIGURATION ---------------------------------------------------------
FONT_FAMILY="PingFang Relaxed TC"
FONT_DIR="$HOME/.local/share/fonts/PingFang"
FONT_REPO="https://github.com/ACT-02/PingFang-Relaxed.git"
FONT_GLOB="*.otf"
FONTCONF_DIR="$HOME/.config/fontconfig/conf.d"
FONTCONF_FILE="$FONTCONF_DIR/30-pingfang-relaxed-tc.conf"
FIREFOX_USER_JS="user.js"
FIREFOX_PROFILE_DIR=""

# ----- LOGGING ---------------------------------------------------------------
info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR]\033[0m %s\n" "$*" >&2; }

# =============================================================================
#  STEP 1 - CHECK IF THE FONT IS ALREADY INSTALLED
# =============================================================================
check_font() {
  info "STEP 1/7 - Checking if 'PingFang Relaxed TC' is already installed..."

  # Capture the grep output. Do NOT use grep -q in a pipeline here.
  # The "|| true" prevents set -e from aborting when grep finds nothing.
  local found
  found=$(fc-list 2>/dev/null | grep -Fi "PingFang Relaxed TC" || true)

  if [[ -n "$found" ]]; then
    info "STEP 1/7 - Font IS already installed. Skipping install step."
    info "          Registered faces (first 5 shown):"
    printf '%s\n' "$found" | head -5 | sed 's/^/            /'
    return 0
  else
    warn "STEP 1/7 - Font is NOT installed yet. Will install in STEP 2."
    return 1
  fi
}

# =============================================================================
#  STEP 2 - DOWNLOAD AND INSTALL THE FONT FILES
# =============================================================================
install_font() {
  info "STEP 2/7 - Downloading and installing PingFang Relaxed TC..."

  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT
  info "STEP 2a  - Using temporary directory: $tmp_dir"

  info "STEP 2b  - Cloning $FONT_REPO ..."
  if ! git clone --depth=1 "$FONT_REPO" "$tmp_dir/PingFangRelaxed"; then
    err "STEP 2b  - git clone failed."
    err "          Check that 'git' is installed and that you have network access."
    exit 1
  fi
  info "STEP 2b  - Clone complete."

  info "STEP 2c  - Copying files matching '$FONT_GLOB' into $FONT_DIR ..."
  mkdir -p "$FONT_DIR"
  find "$tmp_dir/PingFangRelaxed" -name "$FONT_GLOB" -exec cp -v {} "$FONT_DIR/" \;

  if [[ -z "$(ls -A "$FONT_DIR")" ]]; then
    err "STEP 2c  - No files matched '$FONT_GLOB' in the repository."
    exit 1
  fi
  info "STEP 2c  - Files copied. Current contents of $FONT_DIR:"
  find "$FONT_DIR" -mindepth 1 -maxdepth 1 | sort | sed 's/^/            /'

  info "STEP 2d  - Rebuilding Fontconfig cache for $FONT_DIR ..."
  fc-cache -fv "$FONT_DIR" | sed 's/^/            /'
  info "STEP 2d  - Cache rebuild done."
}

# =============================================================================
#  STEP 3 - DETECT THE EXACT FAMILY NAME
# =============================================================================
detect_font_family() {
  info "STEP 3/7 - Detecting the exact font family name from the installed files..."

  local sample_file
  sample_file=$(find "$FONT_DIR" -name "PingFangRelaxedTC-Regular.otf" -print -quit)

  if [[ -z "$sample_file" ]]; then
    warn "STEP 3a  - PingFangRelaxedTC-Regular.otf not found; using any .otf."
    sample_file=$(find "$FONT_DIR" -name "*.otf" -print -quit)
  fi

  if [[ -z "$sample_file" ]]; then
    err "STEP 3a  - No .otf file found in $FONT_DIR at all. Aborting."
    exit 1
  fi
  info "STEP 3a  - Sample file: $sample_file"

  # %{family[0]} gives only the first family name; %{family} would give the
  # whole comma-joined alias list, which is what we do NOT want.
  local detected
  detected=$(fc-scan --format "%{family[0]}\n" "$sample_file" | head -n1 | tr -d '\n')

  if [[ -n "$detected" ]]; then
    FONT_FAMILY="$detected"
    info "STEP 3b  - Fontconfig reports primary family name: '$FONT_FAMILY'"
  else
    warn "STEP 3b  - fc-scan returned nothing; keeping fallback '$FONT_FAMILY'."
  fi

  if [[ "$FONT_FAMILY" == *,* ]]; then
    err "STEP 3b  - Detected family name contains a comma: '$FONT_FAMILY'"
    err "          fc-scan returned multiple families. Aborting."
    exit 1
  fi
}

# =============================================================================
#  STEP 4 - WRITE THE FONTCONFIG RULE
# =============================================================================
configure_fontconfig() {
  info "STEP 4/7 - Writing Fontconfig rule to prefer '$FONT_FAMILY' ..."

  mkdir -p "$FONTCONF_DIR"

  cat >"$FONTCONF_FILE" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer><family>$FONT_FAMILY</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>$FONT_FAMILY</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>$FONT_FAMILY</family></prefer>
  </alias>

  <match target="pattern">
    <test name="lang" compare="contains"><string>zh-tw</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>$FONT_FAMILY</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="lang" compare="contains"><string>zh-hk</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>$FONT_FAMILY</string>
    </edit>
  </match>
</fontconfig>
EOF

  info "STEP 4a  - Wrote: $FONTCONF_FILE"
  sed 's/^/            /' "$FONTCONF_FILE"

  info "STEP 4b  - Rebuilding global Fontconfig cache ..."
  fc-cache -fv | tail -5 | sed 's/^/            /'
  info "STEP 4b  - Cache rebuild done."
}

# =============================================================================
#  STEP 5 - FIND THE FIREFOX PROFILE
# =============================================================================
find_firefox_profile() {
  info "STEP 5/7 - Locating the default Firefox profile ..."

  local ini="$HOME/.mozilla/firefox/profiles.ini"

  if [[ ! -f "$ini" ]]; then
    err "STEP 5a  - $ini not found."
    err "          Launch Firefox once, close it, and re-run this script."
    exit 1
  fi
  info "STEP 5a  - Found profiles.ini: $ini"

  local profile
  profile=$(awk -F= '
    /^\[Profile/{p=1}
    p && /^Default=1/{d=1; next}
    p && d && /^Path=/{print $2; exit}
  ' "$ini")

  if [[ -z "$profile" ]]; then
    warn "STEP 5b  - No Default=1 profile found; using first Path= in the file."
    profile=$(awk -F= '/^\[Profile/{p=1} p && /^Path=/{print $2; exit}' "$ini")
  fi

  if [[ -z "$profile" ]]; then
    err "STEP 5b  - Could not extract any profile path from $ini."
    exit 1
  fi

  FIREFOX_PROFILE_DIR="$HOME/.mozilla/firefox/$profile"

  if [[ ! -d "$FIREFOX_PROFILE_DIR" ]]; then
    err "STEP 5c  - Profile directory does not exist: $FIREFOX_PROFILE_DIR"
    exit 1
  fi
  info "STEP 5c  - Using profile: $FIREFOX_PROFILE_DIR"
}

# =============================================================================
#  STEP 6 - WRITE FIREFOX user.js
# =============================================================================
configure_firefox() {
  info "STEP 6/7 - Writing Firefox user.js ..."

  find_firefox_profile

  local user_js_path="$FIREFOX_PROFILE_DIR/$FIREFOX_USER_JS"

  if [[ -f "$user_js_path" ]]; then
    local backup
    backup="${user_js_path}.bak.$(date +%s)"
    cp "$user_js_path" "$backup"
    info "STEP 6a  - Backed up existing user.js to: $backup"
  else
    info "STEP 6a  - No existing user.js; nothing to back up."
  fi

  cat >"$user_js_path" <<EOF
// PingFang Relaxed TC font preferences for Firefox
// Generated by setup-pingfang-tc-firefox.sh

user_pref("font.name.sans-serif.zh-TW", "$FONT_FAMILY");
user_pref("font.name.serif.zh-TW",      "$FONT_FAMILY");
user_pref("font.name.monospace.zh-TW",  "$FONT_FAMILY");
user_pref("font.name-list.sans-serif.zh-TW", "$FONT_FAMILY, sans-serif");
user_pref("font.name-list.serif.zh-TW",      "$FONT_FAMILY, serif");
user_pref("font.name-list.monospace.zh-TW",  "$FONT_FAMILY, monospace");

user_pref("font.name.sans-serif.zh-HK", "$FONT_FAMILY");
user_pref("font.name.serif.zh-HK",      "$FONT_FAMILY");
user_pref("font.name.monospace.zh-HK",  "$FONT_FAMILY");

user_pref("font.name.sans-serif.zh-CN", "$FONT_FAMILY");
user_pref("font.name.serif.zh-CN",      "$FONT_FAMILY");
user_pref("font.name.monospace.zh-CN",  "$FONT_FAMILY");

user_pref("font.name.sans-serif.ja", "$FONT_FAMILY");
user_pref("font.name.serif.ja",      "$FONT_FAMILY");
user_pref("font.name.monospace.ja",  "$FONT_FAMILY");

user_pref("browser.display.use_document_fonts", 1);
EOF

  info "STEP 6b  - Wrote: $user_js_path"
  sed 's/^/            /' "$user_js_path"
}

# =============================================================================
#  STEP 7 - VERIFY
# =============================================================================
verify() {
  echo
  info "STEP 7/7 - Verification"
  echo "============================================================"

  echo
  info "7a. Fontconfig entries for 'PingFang Relaxed TC':"
  local found
  found=$(fc-list 2>/dev/null | grep -Fi "PingFang Relaxed TC" || true)
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found" | head -10 | sed 's/^/            /'
    info "    ✅ Font is registered."
  else
    err "    ❌ Font not registered in Fontconfig."
  fi

  echo
  info "7b. What 'sans-serif:lang=zh-tw' resolves to (top 3 candidates):"
  fc-match -s "sans-serif:lang=zh-tw" | head -3 | sed 's/^/            /'

  echo
  info "7c. What 'sans-serif:lang=zh-cn' resolves to (top 3 candidates):"
  fc-match -s "sans-serif:lang=zh-cn" | head -3 | sed 's/^/            /'

  echo
  if [[ -n "$FIREFOX_PROFILE_DIR" && -f "$FIREFOX_PROFILE_DIR/$FIREFOX_USER_JS" ]]; then
    info "7d. user.js at $FIREFOX_PROFILE_DIR/$FIREFOX_USER_JS:"
    grep -E "PingFang|use_document_fonts" "$FIREFOX_PROFILE_DIR/$FIREFOX_USER_JS" \
      | sed 's/^/            /'
  else
    warn "7d. user.js not found at expected path."
  fi

  echo
  info "DONE."
  info "Quit Firefox completely and start it again to apply user.js."
}

# =============================================================================
#  MAIN
# =============================================================================
main() {
  echo "============================================================"
  echo " PingFang Relaxed TC setup for Firefox on XFCE"
  echo "============================================================"
  echo

  if ! check_font; then
    install_font
  fi

  detect_font_family
  configure_fontconfig
  configure_firefox
  verify
}

main "$@"
