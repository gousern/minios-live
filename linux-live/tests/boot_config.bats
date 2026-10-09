#!/usr/bin/env bats

setup() {
    LIVE_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    WORK_DIR="${BATS_TEST_TMPDIR}/work"
    BUILD_SCRIPTS_DIR="${LIVE_ROOT}"
    LIVEKITNAME="minios"
    NAMED_BOOT_FILES="false"
    BOOTLOADER="syslinux-native"
    PACKAGE_VARIANT="standard"

    mkdir -p "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/locale"

    source "${LIVE_ROOT}/minioslib"
    current_process() { :; }
    information() { :; }
    warning() { :; }
}

kernel_config_files() {
    printf '%s\n' \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/syslinux/lang/"*.cfg \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.template.cfg"
}

assert_kernel_lines() {
    local expected="${1}"
    local file line count

    while IFS= read -r file; do
        count=0
        while IFS= read -r line; do
            [[ "${line}" == *"${expected}"* ]]
            count=$((count + 1))
        done < <(grep -E '^(APPEND|    linux )' "${file}")
        [ "${count}" -gt 0 ]
    done < <(kernel_config_files)
}

@test "serial console parameters are omitted when disabled" {
    SERIAL_CONSOLE="false"
    create_config_files

    run grep -R -F 'console=ttyS0,115200n8' "${WORK_DIR}/image/${LIVEKITNAME}/boot"
    [ "${status}" -eq 1 ]
    ! grep -R -Fq 'SERIAL 0 115200 0' "${WORK_DIR}/image/${LIVEKITNAME}/boot/syslinux"
    ! grep -R -Fq 'serial --unit=0 --speed=115200' "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub"
}

@test "serial console reaches bootloaders and every generated kernel entry" {
    SERIAL_CONSOLE="true"
    create_config_files

    assert_kernel_lines 'console=tty0 console=ttyS0,115200n8'
    grep -Fxq 'SERIAL 0 115200 0' "${WORK_DIR}/image/${LIVEKITNAME}/boot/syslinux/syslinux.multilang.cfg"
    for file in "${WORK_DIR}/image/${LIVEKITNAME}/boot/syslinux/lang/"*.cfg; do
        grep -Fxq 'SERIAL 0 115200 0' "${file}"
    done
    for file in \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.multilang.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.template.cfg"; do
        grep -Fxq 'if [ "$grub_platform" = "pc" ]; then' "${file}"
        grep -Fxq '    serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1' "${file}"
        grep -Fxq '    terminal_input console serial' "${file}"
        grep -Fxq '    terminal_output gfxterm serial' "${file}"
        grep -Fxq 'fi' "${file}"
        if command -v grub-script-check >/dev/null 2>&1; then
            grub-script-check "${file}"
        fi
    done

    grep -Fq '"serial.mod" "terminfo.mod" "acpi.mod"' "${LIVE_ROOT}/minioslib"
}

@test "Secure Boot falls back to GRUB embedded unicode font" {
    SERIAL_CONSOLE="false"
    create_config_files

    for file in \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.multilang.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.template.cfg"; do
        grep -Fxq 'if [ "$lockdown" = "y" ]; then' "${file}"
        grep -Fxq '    loadfont (memdisk)/fonts/unicode.pf2' "${file}"
        grep -Fxq '    insmod font' "${file}"
        ! grep -Fq 'if ! loadfont' "${file}"
        ! grep -Fq 'set lockdown=' "${file}"
        if command -v grub-script-check >/dev/null 2>&1; then
            grub-script-check "${file}"
        fi
    done
}

@test "GRUB 2.12 graphics are initialized before theme loading" {
    SERIAL_CONSOLE="false"
    create_config_files

    for file in \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.multilang.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.template.cfg"; do
        grep -Fxq 'echo -n ""' "${file}"
        first_init=$(grep -n -F 'echo -n ""' "${file}" | head -n1 | cut -d: -f1)
        first_theme=$(grep -n -E '^[[:space:]]*set theme=' "${file}" | head -n1 | cut -d: -f1)
        [ -n "${first_init}" ]
        [ -n "${first_theme}" ]
        [ "${first_init}" -lt "${first_theme}" ]
    done
}

@test "accepted menu keeps Start MiniOS as automatic default" {
    SERIAL_CONSOLE="false"
    create_config_files

    grep -Fxq 'set resume=$"Start MiniOS"' \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg"
    grep -Fq 'menuentry "$resume" --class resume' \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg"
    grep -Fq 'menuentry "Start MiniOS" --class resume' \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.template.cfg"
    grep -Fq 'perchdir=resume' "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg"
    grep -Fq 'perchdir=resume' "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.template.cfg"
    grep -Fq 'local RESUME="Start MiniOS"' "${LIVE_ROOT}/minioslib"
    grep -Fq 'local CHOOSE_SESSION="Choose a saved session"' "${LIVE_ROOT}/minioslib"
    grep -Fq 'local FRESH_START="Start without saving"' "${LIVE_ROOT}/minioslib"
    grep -Fq 'local COPY_RAM="Run from RAM"' "${LIVE_ROOT}/minioslib"
}

@test "GRUB menu boots AUFS by default and offers an OverlayFS submenu" {
    SERIAL_CONSOLE="false"
    create_config_files

    local file
    for file in \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/main.cfg" \
        "${WORK_DIR}/image/${LIVEKITNAME}/boot/grub/grub.template.cfg"; do
        # Six entries per union filesystem, the second set behind one submenu
        [ "$(grep -cE '^    linux .*union=aufs' "${file}")" -eq 6 ]
        [ "$(grep -cE '^    linux .*union=overlayfs' "${file}")" -eq 6 ]
        grep -Fq 'submenu "Boot with OverlayFS (default: AUFS)" {' "${file}"
        # The blank persistence image can be formatted from the menu itself
        [ "$(grep -c 'perchformat=1' "${file}")" -eq 2 ]
        grep -cE '^    linux .*union=aufs .*perchformat=1' "${file}" | grep -Fxq 1
        grep -cE '^    linux .*union=overlayfs .*perchformat=1' "${file}" | grep -Fxq 1
        grep -Fq 'Start MiniOS and create the persistence image' "${file}"
        # The entry GRUB selects automatically is the first AUFS one
        grep -E '^    linux ' "${file}" | head -n 1 | grep -Fq 'union=aufs'
        if command -v grub-script-check >/dev/null 2>&1; then
            grub-script-check "${file}"
        fi
    done
}

@test "SYSLINUX menu boots AUFS and links to an OverlayFS twin" {
    SERIAL_CONSOLE="false"
    create_config_files

    local lang_dir="${WORK_DIR}/image/${LIVEKITNAME}/boot/syslinux/lang"
    local base twin

    [ "$(find "${lang_dir}" -name '*.cfg' | wc -l)" -eq 18 ]

    for base in "${lang_dir}"/*.cfg; do
        case "${base}" in
        *-overlayfs.cfg) continue ;;
        esac
        twin="${base%.cfg}-overlayfs.cfg"
        [ -f "${twin}" ]

        grep -Fq 'MENU ROWS 6' "${base}"
        [ "$(grep -cE '^APPEND .*union=aufs' "${base}")" -eq 5 ]
        [ "$(grep -cE '^APPEND .*union=overlayfs' "${base}")" -eq 0 ]
        grep -Fq 'switch to OverlayFS' "${base}"
        grep -Fq "CONFIG lang/$(basename "${twin}")" "${base}"

        [ "$(grep -cE '^APPEND .*union=overlayfs' "${twin}")" -eq 5 ]
        [ "$(grep -cE '^APPEND .*union=aufs' "${twin}")" -eq 0 ]
        grep -Fq 'switch to AUFS (default)' "${twin}"
        grep -Fq "CONFIG lang/$(basename "${base}")" "${twin}"
    done
}
