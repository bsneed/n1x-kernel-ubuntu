#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - tests for the version parsing, command line and GRUB helpers
#
# Why: scripts/install.sh edits /etc/default/grub and picks GRUB entries with these helpers;
# a mistake there leaves a laptop booting the wrong kernel or without the USB4 parameters.
# Remove: nothing to remove; it only uses a temporary directory.
# Run with: bash tests/run.sh   (bash 4.4 or newer)
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh
. scripts/grub.sh

pass=0 failed=0
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

eq() { # eq NAME EXPECTED ACTUAL
	if [[ $2 == "$3" ]]; then
		pass=$((pass + 1))
	else
		failed=$((failed + 1))
		printf 'FAIL %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
	fi
}
fails() { # fails NAME COMMAND...: the command must exit non-zero
	local name=$1
	shift
	if ("$@") >/dev/null 2>&1; then
		failed=$((failed + 1))
		printf 'FAIL %s: expected a failure\n' "$name"
	else
		pass=$((pass + 1))
	fi
}

P=pci=hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=32G
OSI='acpi_osi=\"!Windows 2022\"'

# --- versions --------------------------------------------------------------------------------
eq "base of X.Y" 7.3.0 "$(kernel_base_version 7.3)"
eq "base of X.Y.Z" 7.3.5 "$(kernel_base_version 7.3.5)"
eq "base of 10.12" 10.12.0 "$(kernel_base_version 10.12)"
fails "base rejects X" kernel_base_version 7
fails "base rejects rc" kernel_base_version 7.3-rc1
fails "base rejects X.Y.Z.W" kernel_base_version 7.3.1.2
fails "base rejects empty" kernel_base_version ""
eq "release" 7.3.0-n1x1 "$(kernel_release 7.3 1)"
eq "release two digits" 7.3.5-n1x12 "$(kernel_release 7.3.5 12)"
fails "release rejects revision 0" kernel_release 7.3 0
fails "release rejects revision 01" kernel_release 7.3 01
fails "release rejects revision x" kernel_release 7.3 x
eq "is ours" 0 "$(is_n1x_release 7.3.0-n1x1; echo $?)"
eq "1026 is not ours" 1 "$(is_n1x_release 7.0.0-1026-nvidia; echo $?)"
eq "suffix is not ours" 1 "$(is_n1x_release 7.3.0-n1x1-foo; echo $?)"
eq "generic is not ours" 1 "$(is_n1x_release 7.0.0-44-generic; echo $?)"

# --- sources ---------------------------------------------------------------------------------
load_sources
eq "pinned release" "7.3.0-n1x$N1X_REVISION" "$(kernel_release "$KERNEL_VERSION" "$N1X_REVISION")"
grep -v '^NVIDIA_URL=' sources >"$T/sources"
# shellcheck disable=SC2016 # expanded by the inner bash
fails "load_sources needs every key" bash -c '. scripts/lib.sh; load_sources "$1"' _ "$T/sources"
fails "load_sources needs the file" load_sources "$T/missing"
printf 'x' >"$T/f"
fails "verify_sha256 mismatch" verify_sha256 "$T/f" 0000
eq "verify_sha256 match" ok "$(verify_sha256 "$T/f" 2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881 && echo ok)"

# --- cmdline: add ----------------------------------------------------------------------------
eq "add to Ubuntu default" "quiet splash $P" "$(cmdline_add_pci "quiet splash")"
eq "add to empty" "$P" "$(cmdline_add_pci "")"
eq "add to spaces" "$P" "$(cmdline_add_pci "  ")"
eq "add keeps the quoted acpi_osi" "quiet splash console=tty0 $OSI $P" \
	"$(cmdline_add_pci "quiet splash console=tty0 $OSI")"
eq "add is idempotent" "quiet $P" "$(cmdline_add_pci "$(cmdline_add_pci quiet)")"
eq "add with param already present" "quiet $P splash" "$(cmdline_add_pci "quiet $P splash")"
eq "add merges another pci= option" "quiet pci=realloc,hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=32G" \
	"$(cmdline_add_pci "quiet pci=realloc")"
eq "add replaces a different value" "pci=hpbussize=0x80,realloc,hpmmiosize=32M,hpmmioprefsize=32G x" \
	"$(cmdline_add_pci "pci=hpbussize=0x20,realloc x")"
eq "add edits the last pci=" "pci=noaer a pci=realloc,$(echo "$P" | cut -d= -f2-) b" \
	"$(cmdline_add_pci "pci=noaer a pci=realloc b")"
eq "add keeps double spaces" "a  b $P" "$(cmdline_add_pci "a  b")"
eq "add ignores look-alikes" "nopci=1 xpci=2 $P" "$(cmdline_add_pci "nopci=1 xpci=2")"
eq "add to empty pci=" "a $P" "$(cmdline_add_pci "a pci=")"

# --- cmdline: remove -------------------------------------------------------------------------
eq "remove ours" "quiet splash" "$(cmdline_remove_pci "quiet splash $P")"
eq "remove from the middle" "quiet splash" "$(cmdline_remove_pci "quiet $P splash")"
eq "remove only" "" "$(cmdline_remove_pci "$P")"
eq "remove keeps others' options" "quiet pci=realloc" \
	"$(cmdline_remove_pci "quiet pci=realloc,hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=32G")"
eq "remove keeps a different value" "pci=hpbussize=0x20" "$(cmdline_remove_pci "pci=hpbussize=0x20")"
eq "remove when absent" "quiet splash $OSI" "$(cmdline_remove_pci "quiet splash $OSI")"
eq "remove from every pci=" "a b" "$(cmdline_remove_pci "a $P b $P")"
eq "remove round trip" "quiet splash console=tty0 $OSI" \
	"$(cmdline_remove_pci "$(cmdline_add_pci "quiet splash console=tty0 $OSI")")"
eq "remove round trip with realloc" "pci=realloc q" "$(cmdline_remove_pci "$(cmdline_add_pci "pci=realloc q")")"
eq "remove from empty" "" "$(cmdline_remove_pci "")"

# --- /etc/default/grub -----------------------------------------------------------------------
cat >"$T/grub" <<'EOF'
GRUB_DEFAULT=saved
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=tty0 acpi_osi=\"!Windows 2022\""
GRUB_CMDLINE_LINUX=""
EOF
eq "get" 'quiet splash console=tty0 acpi_osi=\"!Windows 2022\"' "$(grub_default_get "$T/grub")"
grub_default_set "$T/grub" "$(cmdline_add_pci "$(grub_default_get "$T/grub")")"
eq "set writes the line" "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash console=tty0 $OSI $P\"" \
	"$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$T/grub")"
eq "set keeps the other lines" 4 "$(wc -l <"$T/grub" | tr -d ' ')"
eq "set keeps GRUB_CMDLINE_LINUX" 'GRUB_CMDLINE_LINUX=""' "$(grep '^GRUB_CMDLINE_LINUX=' "$T/grub")"
grub_default_set "$T/grub" "$(cmdline_add_pci "$(grub_default_get "$T/grub")")"
eq "set twice is idempotent" 1 "$(grep -c "$P" "$T/grub")"
grub_default_set "$T/grub" "$(cmdline_remove_pci "$(grub_default_get "$T/grub")")"
eq "set back" 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=tty0 acpi_osi=\"!Windows 2022\""' \
	"$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$T/grub")"
printf 'GRUB_DEFAULT=0\n' >"$T/grub2"
eq "get when unset" "" "$(grub_default_get "$T/grub2")"
grub_default_set "$T/grub2" "$P"
eq "set appends when unset" "GRUB_CMDLINE_LINUX_DEFAULT=\"$P\"" "$(tail -1 "$T/grub2")"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="a"\nGRUB_CMDLINE_LINUX_DEFAULT="b"\n' >"$T/grub3"
eq "get uses the last line" b "$(grub_default_get "$T/grub3")"
grub_default_set "$T/grub3" c
eq "set edits the last line" 'GRUB_CMDLINE_LINUX_DEFAULT="a"|GRUB_CMDLINE_LINUX_DEFAULT="c"' \
	"$(paste -sd'|' "$T/grub3")"
printf "GRUB_CMDLINE_LINUX_DEFAULT='quiet'\n" >"$T/grub4"
fails "get rejects single quotes" grub_default_get "$T/grub4"
fails "get on a missing file" grub_default_get "$T/nope"
fails "set on a missing file" grub_default_set "$T/nope" x
eq "set creates no stray file" "" "$(find "$T" -name 'nope*')"

# --- grub.cfg entries ------------------------------------------------------------------------
U=6c6094c7-bf28-4bf8-946b-1d5cedbd3d22
cat >"$T/grub.cfg" <<EOF
menuentry 'Ubuntu' --class ubuntu \$menuentry_id_option 'gnulinux-simple-$U' {
}
submenu 'Advanced options for Ubuntu' \$menuentry_id_option 'gnulinux-advanced-$U' {
	menuentry 'Ubuntu, with Linux 7.3.0-n1x1' --class ubuntu \$menuentry_id_option 'gnulinux-7.3.0-n1x1-advanced-$U' {
	}
	menuentry 'Ubuntu, with Linux 7.3.0-n1x1 (recovery mode)' \$menuentry_id_option 'gnulinux-7.3.0-n1x1-recovery-$U' {
	}
	menuentry 'Ubuntu, with Linux 7.0.0-1026-nvidia' \$menuentry_id_option 'gnulinux-7.0.0-1026-nvidia-advanced-$U' {
	}
	menuentry 'Ubuntu, with Linux 7.0.0-1026-nvidia-64k' \$menuentry_id_option 'gnulinux-7.0.0-1026-nvidia-64k-advanced-$U' {
	}
}
menuentry 'Windows Boot Manager (on /dev/nvme0n1p1)' \$menuentry_id_option 'osprober-efi-803E-D421' {
}
EOF
eq "entry for ours" "gnulinux-advanced-$U>gnulinux-7.3.0-n1x1-advanced-$U" "$(grub_entry_id "$T/grub.cfg" 7.3.0-n1x1)"
eq "entry for 1026, not its -64k sibling" "gnulinux-advanced-$U>gnulinux-7.0.0-1026-nvidia-advanced-$U" \
	"$(grub_entry_id "$T/grub.cfg" 7.0.0-1026-nvidia)"
fails "entry for a missing kernel" grub_entry_id "$T/grub.cfg" 7.0.0-44-generic
fails "entry needs the dots to match" grub_entry_id "$T/grub.cfg" 7x3x0-n1x1
fails "entry in a missing grub.cfg" grub_entry_id "$T/none.cfg" 7.3.0-n1x1

# --- config-check.sh -------------------------------------------------------------------------
printf 'CONFIG_A=y\n# CONFIG_B is not set\nCONFIG_C="x y"\nCONFIG_D=m\n' >"$T/.config"
printf '# comment\nCONFIG_A=y\n# CONFIG_B is not set\nCONFIG_C="x y"\n# CONFIG_E is not set\n' >"$T/good.frag"
eq "config-check passes" 0 "$(bash scripts/config-check.sh "$T/good.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf 'CONFIG_D=y\n' >"$T/bad.frag"
eq "config-check catches a changed value" 1 "$(bash scripts/config-check.sh "$T/bad.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf 'CONFIG_Z=m\n' >"$T/gone.frag"
eq "config-check catches a dropped option" 1 "$(bash scripts/config-check.sh "$T/gone.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf '# CONFIG_A is not set\n' >"$T/off.frag"
eq "config-check catches an option left on" 1 "$(bash scripts/config-check.sh "$T/off.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf '# nothing\n' >"$T/empty.frag"
eq "config-check rejects an empty fragment" 1 "$(bash scripts/config-check.sh "$T/empty.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
eq "config-check rejects a missing config" 2 "$(bash scripts/config-check.sh "$T/good.frag" "$T/none" >/dev/null 2>&1; echo $?)"

echo "tests: $pass passed, $failed failed"
[[ $failed -eq 0 ]]
