#!/usr/bin/env bash
# 验证本次改动是否真的进了 ISO：ISO 内是分层 squashfs (*.sb)，按模块抽取目标文件。
# 用法: ./verify-iso.sh /path/to/xxx.iso
set -u
ISO=${1:?用法: $0 xxx.iso}
WORK=$(mktemp -d /var/tmp/isoverify.XXXXXX)
echo "工作目录: $WORK"

echo "== 1. 解出 ISO =="
xorriso -osirrox on -indev "$ISO" -extract / "$WORK/iso" >/dev/null 2>&1
mapfile -t MODS < <(find "$WORK/iso" -name '*.sb' -o -name '*.squashfs' | sort)
[ ${#MODS[@]} -gt 0 ] || { echo "!! 找不到 .sb 模块"; exit 1; }
echo "找到 ${#MODS[@]} 个模块"

echo "== 2. 建索引 (每个模块的文件清单) =="
for m in "${MODS[@]}"; do
  b=$(basename "$m")
  unsquashfs -l "$m" 2>/dev/null | sed 's#^squashfs-root/##' | awk -v mod="$b" 'NF{print mod"\t"$1}' >"$WORK/idx.$b"
done
cat "$WORK"/idx.* >"$WORK/index"
find_mod() { grep -P "\t$1/?$" "$WORK/index" | head -1 | cut -f1; }

declare -A TARGETS=(
  [user-dirs.dirs]="etc/skel/.config/user-dirs.dirs"
  [skel-bin]="etc/skel/bin"
  [policies.lib]="usr/lib/firefox-esr/distribution/policies.json"
  [policies.share]="usr/share/firefox-esr/distribution/policies.json"
  [minios.js]="usr/lib/firefox-esr/defaults/pref/minios.js"
  [extensions-dir]="usr/share/minios/firefox-extensions"
  [root-crontab]="var/spool/cron/crontabs/root"
  [config0030]="usr/lib/live/config/0030-user-setup"
  [mise-toml]="home/live/.mise.toml"
  [mise-bin]="usr/local/bin/mise"
  [xfce-desktop-xml]="etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
)
echo "== 3. 定位目标文件所在模块 =="
declare -A MOD_OF
for k in "${!TARGETS[@]}"; do
  mod=$(find_mod "${TARGETS[$k]}")
  MOD_OF[$k]="$mod"
  echo "  $k -> ${mod:-未找到}"
done

echo "== 4. 抽取 =="
for k in "${!TARGETS[@]}"; do
  [ -n "${MOD_OF[$k]}" ] || continue
  unsquashfs -f -d "$WORK/root.$k" "$WORK/iso/minios/${MOD_OF[$k]}" "${TARGETS[$k]}" >/dev/null 2>&1
done

echo "== 4b. 各层 dpkg status (查语言包) =="
while read -r m; do
  unsquashfs -f -d "$WORK/st.$m" "$WORK/iso/minios/$m" var/lib/dpkg/status >/dev/null 2>&1 || true
done < <(grep -P "\tvar/lib/dpkg/status$" "$WORK/index" | cut -f1)
cat "$WORK"/st.*/var/lib/dpkg/status 2>/dev/null | grep -E '^Package: firefox-esr-l10n-' \
  | sed 's/^Package: //' | sort -u >"$WORK/l10n.list"
echo "     镜像里的 firefox 语言包: $(tr '\n' ' ' <"$WORK/l10n.list")"

pass=0; fail=0
chk() { local d=$1; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $d"; pass=$((pass+1)); else echo "  [FAIL] $d"; fail=$((fail+1)); fi; }
R() { echo "$WORK/root.$1/${TARGETS[$1]}"; }

echo "== 5. 检查项 =="
echo "-- 040-xdg-user-dirs: skel 瘦身 + bin --"
F=$(R user-dirs.dirs)
if [ -f "$F" ]; then
  echo "     /etc/skel/.config/user-dirs.dirs 内容:"; sed 's/^/       /' "$F"
  chk "只剩 Desktop + Download" bash -c "grep -c '^XDG_.*_DIR' '$F' | grep -qx 2"
  chk "无 Templates/Public/Music/Videos/Pictures 残留" \
      bash -c "! grep -qE 'TEMPLATES|PUBLICSHARE|MUSIC|VIDEOS|PICTURES|DOCUMENTS' '$F'"
else echo "  [FAIL] user-dirs.dirs 不在镜像里"; fail=$((fail+1)); fi
chk "/etc/skel/bin 存在" test -d "$(R skel-bin)"

echo "-- 10-firefox: policies + 主题 + 扩展 --"
P=$(R policies.share); [ -f "$P" ] || P=$(R policies.lib)
if [ -f "$P" ]; then
  echo "     policies.json 关键内容:"; grep -E 'force_installed|install_url|"' "$P" | grep -E 'sqyt|foxpilot|830f38bd|force_installed' | sed 's/^/       /'
  chk "3 个 force_installed" bash -c "[ \$(grep -c force_installed '$P') -eq 3 ]"
else echo "  [FAIL] policies.json 不在镜像里"; fail=$((fail+1)); fi
M=$(R minios.js)
chk "minios.js (默认暗色主题) 存在" test -f "$M"
[ -f "$M" ] && grep -H activeThemeID "$M" | sed 's/^/       /'
E=$(R extensions-dir)
chk "3 个 xpi 已进镜像" bash -c "[ \$(find '$E' -name '*.xpi' 2>/dev/null | wc -l) -eq 3 ]"
if [ -f "$E/SOURCES.txt" ]; then
  echo "     xpi sha256 校验 (vs SOURCES.txt):"
  (cd "$E" && awk '!/^#/ && NF>=3 {print $3"  "$1".xpi"}' SOURCES.txt | sha256sum -c - 2>&1 | sed 's/^/       /')
fi

echo "-- 00-core: root crontab --"
C=$(R root-crontab)
if [ -f "$C" ]; then
  echo "     /var/spool/cron/crontabs/root:"; sed 's/^/       /' "$C"
  chk "包含 apt 升级任务" grep -qi "apt" "$C"
else echo "  [FAIL] root crontab 不在镜像里"; fail=$((fail+1)); fi

echo "-- 0030 (minios-live-config 包) --"
T=$(R config0030)
if [ -f "$T" ]; then
  grep -n "DEFAULT_HOME_DIRS\|user-dirs.dirs" "$T" | head -6 | sed 's/^/       /'
  chk "含 DEFAULT_HOME_DIRS 分支(本次子模块改动)" grep -q "DEFAULT_HOME_DIRS" "$T"
  # 慢启动根因: 无条件 chown -R 会在 OverlayFS 上逐项全量 copy-up
  chk "chown 已改为 find 守卫 (0030)" grep -qF 'find "/home/${LIVE_USERNAME}"' "$T"
  chk "无条件 chown -R 已移除 (0030)" bash -c "! grep -qF 'chown -R \${LIVE_USERNAME}:\${LIVE_USERNAME} /home/\${LIVE_USERNAME}' '$T'"
else echo "  [FAIL] 0030-user-setup 不在镜像里"; fail=$((fail+1)); fi

echo "-- /home/live 属主烘焙 (防首启 chown 全量 copy-up) --"
HCHECK="$WORK/homecheck.list"
: >"$HCHECK"
for m in "${MODS[@]}"; do
  b=$(basename "$m")
  unsquashfs -lln "$m" 2>/dev/null | awk -v mod="$b" '$6 ~ /^squashfs-root\/home\/live(\/|$)/ {print mod"\t"$2"\t"$6}' >>"$HCHECK"
done
if [ -s "$HCHECK" ]; then
  HN=$(wc -l <"$HCHECK")
  HBAD=$(awk -F'\t' '$2 != "1000/1000"' "$HCHECK" | wc -l)
  echo "     镜像内 home/live 条目: $HN, 非 1000/1000: $HBAD"
  [ "$HBAD" -gt 0 ] && awk -F'\t' '$2 != "1000/1000"' "$HCHECK" | head -5 | sed 's/^/       /'
  chk "home/live 全部烘焙为 1000/1000" test "$HBAD" -eq 0
else
  echo "  [FAIL] 镜像里没有 home/live 条目"; fail=$((fail+1))
fi

echo "-- GRUB/SYSLINUX 启动菜单 (AUFS + OverlayFS 双入口) --"
GB="$WORK/iso/minios/boot/grub/main.cfg"
SB="$WORK/iso/minios/boot/syslinux"
if [ -f "$GB" ]; then
  chk "main.cfg 含 union=aufs 菜单项" grep -q 'union=aufs' "$GB"
  chk "main.cfg 含 union=overlayfs 子菜单" bash -c "grep -q 'submenu.*OverlayFS' '$GB' && grep -q 'union=overlayfs' '$GB'"
  chk "main.cfg 含 persistence image 创建项 (aufs+overlayfs 各一)" bash -c "[ \$(grep -c 'perchformat=1' '$GB') -eq 2 ]"
else echo "  [FAIL] grub main.cfg 不在 ISO 里"; fail=$((fail+1)); fi
if [ -d "$SB/lang" ]; then
  NL=$(find "$SB/lang" -name '*.cfg' ! -name '*-overlayfs.cfg' | wc -l)
  NO=$(find "$SB/lang" -name '*-overlayfs.cfg' | wc -l)
  chk "每个语种都有 overlayfs 双生菜单 ($NL/$NO)" test "$NL" -eq "$NO"
  chk "syslinux en_US.cfg 含 union=aufs" grep -q 'union=aufs' "$SB/lang/en_US.cfg"
  chk "syslinux en_US-overlayfs.cfg 含 union=overlayfs" grep -q 'union=overlayfs' "$SB/lang/en_US-overlayfs.cfg"
else echo "  [FAIL] syslinux lang 目录不在 ISO 里"; fail=$((fail+1)); fi

echo "-- mise: 二进制 + 配置 + 工具烘焙 --"
MISE_BIN=$(R mise-bin)
if [ -f "$MISE_BIN" ]; then
  chk "mise 二进制存在 (usr/local/bin/mise)" test -f "$MISE_BIN"
else echo "  [FAIL] mise 不在镜像里"; fail=$((fail+1)); fi
MISE_TOML=$(R mise-toml)
if [ -f "$MISE_TOML" ]; then
  echo "     .mise.toml 内容:"; sed 's/^/       /' "$MISE_TOML"
  chk ".mise.toml 存在于 ISO" test -f "$MISE_TOML"
  chk ".mise.toml 声明了 13 个工具" bash -c "[ \$(grep -cE '^[a-z\"]' '$MISE_TOML') -ge 13 ]"
else echo "  [FAIL] .mise.toml 不在镜像里"; fail=$((fail+1)); fi
# 13 个工具是否真的烘焙进 /home/live (07-customs 的 mise install 产物)
MISE_INST=0
for T in gh node bats black pi ruff shellcheck shfmt lima microsandbox uv python; do
  grep -qP "\thome/live/.local/share/mise/installs/$T(/|\$)" "$WORK/index" && MISE_INST=$((MISE_INST+1))
done
grep -qP "\thome/live/.local/share/mise/installs/aqua-firecracker-microvm-firecracker(/|\$)" "$WORK/index" \
  && MISE_INST=$((MISE_INST+1))
chk "13 个 mise 工具已烘焙进镜像 (找到 $MISE_INST/13)" test "$MISE_INST" -eq 13

echo "-- xfce4-desktop: 背景图 zoom 模式 --"
XD=$(R xfce-desktop-xml)
if [ -f "$XD" ]; then
  echo "     xfce4-desktop.xml 关键行:"; grep -E 'last-image|image-style' "$XD" | head -6 | sed 's/^/       /'
  chk "xfce4-desktop.xml 存在于 ISO" test -f "$XD"
  chk "使用 last-image (现代格式)" grep -q "last-image" "$XD"
  chk "image-style=5 (zoom 模式)" grep -q 'image-style.*5' "$XD"
  # last-image 指向的背景图必须真实存在 (按变体动态判断)
  WALL=$(grep -oP 'last-image" type="string" value="\K[^"]+' "$XD" | head -1)
  chk "last-image 背景图存在于镜像 (${WALL##*/})" grep -qP "\t${WALL#/}\$" "$WORK/index"
else echo "  [FAIL] xfce4-desktop.xml 不在镜像里"; fail=$((fail+1)); fi

echo "-- 10-firefox: 语言包 (只留英语+中文) --"
chk "含中文繁体 firefox-esr-l10n-zh-tw" grep -qx "firefox-esr-l10n-zh-tw" "$WORK/l10n.list"
chk "含中文简体 firefox-esr-l10n-zh-cn" grep -qx "firefox-esr-l10n-zh-cn" "$WORK/l10n.list"
chk "旧 7 个 (de/es/fr/it/pt/ru/id) 已移除" \
    bash -c "! grep -qE 'l10n-(de|es-es|fr|id|it|pt-br|ru)$' '$WORK/l10n.list'"

echo
echo "== 结果: $pass 通过 / $fail 失败 =="
echo "解出的 ISO 留在 $WORK/iso，各模块 root 在 $WORK/root.*"
# Non-zero exit when a check failed, so CI can gate on this.
[ "$fail" -eq 0 ] || exit 1
