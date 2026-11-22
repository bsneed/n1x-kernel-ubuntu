# SPDX-License-Identifier: GPL-2.0-only
# Tests of grub.sh's /etc/default/grub and grub.cfg helpers.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash

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
