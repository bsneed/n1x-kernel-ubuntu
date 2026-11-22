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

# --- GRUB_DEFAULT (the fallback boot needs saved) ---------------------------------------------
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\n' >"$T/gd0"
cp "$T/gd0" "$T/gd0.before"
eq "use saved replaces 0" "GRUB_DEFAULT=0" "$(grub_use_saved "$T/gd0")"
eq "use saved writes saved" "GRUB_DEFAULT=saved|GRUB_TIMEOUT=5" "$(paste -sd'|' "$T/gd0")"
eq "use saved twice is a no-op" "" "$(grub_use_saved "$T/gd0")"
eq "get GRUB_DEFAULT" saved "$(grub_var_get "$T/gd0" GRUB_DEFAULT)"
grub_restore_default "$T/gd0" "$T/gd0.before"
eq "restore puts 0 back" "GRUB_DEFAULT=0|GRUB_TIMEOUT=5" "$(paste -sd'|' "$T/gd0")"
printf 'GRUB_DEFAULT=saved\nGRUB_SAVEDEFAULT=true\n' >"$T/gds"
cp "$T/gds" "$T/gds.before"
eq "use saved keeps saved" "" "$(grub_use_saved "$T/gds")"
grub_restore_default "$T/gds" "$T/gds.before"
eq "restore keeps a saved that was there" "GRUB_DEFAULT=saved|GRUB_SAVEDEFAULT=true" "$(paste -sd'|' "$T/gds")"
printf 'GRUB_DEFAULT="saved"\n' >"$T/gdq"
eq "use saved reads a quoted saved" "" "$(grub_use_saved "$T/gdq")"
printf 'GRUB_TIMEOUT=5\n' >"$T/gdu"
cp "$T/gdu" "$T/gdu.before"
eq "use saved when unset" "GRUB_DEFAULT unset" "$(grub_use_saved "$T/gdu")"
eq "use saved appends when unset" "GRUB_TIMEOUT=5|GRUB_DEFAULT=saved" "$(paste -sd'|' "$T/gdu")"
grub_restore_default "$T/gdu" "$T/gdu.before"
eq "restore deletes the line it added" "GRUB_TIMEOUT=5" "$(paste -sd'|' "$T/gdu")"
printf "GRUB_DEFAULT='Advanced options for Ubuntu>Ubuntu, with Linux 7.0.0-1026-nvidia'\n" >"$T/gdn"
cp "$T/gdn" "$T/gdn.before"
eq "use saved replaces a named entry" "GRUB_DEFAULT='Advanced options for Ubuntu>Ubuntu, with Linux 7.0.0-1026-nvidia'" \
	"$(grub_use_saved "$T/gdn")"
grub_restore_default "$T/gdn" "$T/gdn.before"
eq "restore puts the named entry back" "$(cat "$T/gdn.before")" "$(cat "$T/gdn")"
grub_use_saved "$T/gd0" >/dev/null
printf 'GRUB_DEFAULT=2\nGRUB_TIMEOUT=5\n' >"$T/gd0"
grub_restore_default "$T/gd0" "$T/gd0.before"
eq "restore keeps a value the user changed since" "GRUB_DEFAULT=2|GRUB_TIMEOUT=5" "$(paste -sd'|' "$T/gd0")"
# shellcheck disable=SC2016 # a literal $(...) in the file
printf 'GRUB_DEFAULT=$(echo 0)\n' >"$T/gdx"
fails "get rejects a command substitution" grub_var_get "$T/gdx" GRUB_DEFAULT
fails "use saved rejects what it cannot read" grub_use_saved "$T/gdx"

# --- forms grub-mkconfig honours but the plain-line edit would miss ----------------------------
printf 'GRUB_DEFAULT=0\n  GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' >"$T/gi"
fails "get rejects an indented assignment" grub_default_get "$T/gi"
printf 'export GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' >"$T/ge"
fails "get rejects an exported assignment" grub_default_get "$T/ge"
printf 'GRUB_DEFAULT=0\n\texport GRUB_DEFAULT=saved\n' >"$T/gde"
fails "GRUB_DEFAULT get rejects an indented export" grub_var_get "$T/gde" GRUB_DEFAULT
printf '#GRUB_CMDLINE_LINUX_DEFAULT="x"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' >"$T/gc"
eq "get ignores a commented-out line" quiet "$(grub_default_get "$T/gc")"
mkdir -p "$T/grub.d"
# shellcheck disable=SC2016 # a literal $GRUB_CMDLINE_LINUX_DEFAULT in the file
printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT crashkernel=2G-4G:320M"\n' >"$T/grub.d/kdump-tools.cfg"
printf 'GRUB_TIMEOUT=0\n' >"$T/grub.d/10-timeout.cfg"
printf 'not a cfg\n' >"$T/grub.d/README"
eq "drop-ins that extend the value are fine" "" "$(grub_dropin_overrides "$T/grub.d" GRUB_CMDLINE_LINUX_DEFAULT)"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0"\n' >"$T/grub.d/50-cloudimg-settings.cfg"
printf 'GRUB_DEFAULT=0\n' >"$T/grub.d/60-default.cfg"
eq "drop-in that replaces the cmdline" "$T/grub.d/50-cloudimg-settings.cfg: GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0\"" \
	"$(grub_dropin_overrides "$T/grub.d" GRUB_CMDLINE_LINUX_DEFAULT)"
eq "drop-in that sets GRUB_DEFAULT" "$T/grub.d/60-default.cfg: GRUB_DEFAULT=0" "$(grub_dropin_overrides "$T/grub.d" GRUB_DEFAULT)"
eq "no drop-in directory" "" "$(grub_dropin_overrides "$T/no-grub.d" GRUB_DEFAULT)"

# --- the command line grub.cfg got ------------------------------------------------------------
cat >"$T/linux.cfg" <<EOF
submenu 'Advanced options for Ubuntu' \$menuentry_id_option 'gnulinux-advanced-$U' {
	menuentry 'Ubuntu, with Linux 7.3.0-n1x1' --class ubuntu \$menuentry_id_option 'gnulinux-7.3.0-n1x1-advanced-$U' {
		echo	'Loading Linux 7.3.0-n1x1 ...'
		linux	/vmlinuz-7.3.0-n1x1 root=UUID=$U ro quiet splash $P \$vt_handoff
	}
	menuentry 'Ubuntu, with Linux 7.3.0-n1x1 (recovery mode)' \$menuentry_id_option 'gnulinux-7.3.0-n1x1-recovery-$U' {
		linux	/vmlinuz-7.3.0-n1x1 root=UUID=$U ro recovery nomodeset
	}
	menuentry 'Ubuntu, with Linux 7.0.0-1026-nvidia-64k' \$menuentry_id_option 'gnulinux-7.0.0-1026-nvidia-64k-advanced-$U' {
		linux	/vmlinuz-7.0.0-1026-nvidia-64k root=UUID=$U ro quiet $P
	}
	menuentry 'Ubuntu, with Linux 7.0.0-1026-nvidia' \$menuentry_id_option 'gnulinux-7.0.0-1026-nvidia-advanced-$U' {
		linux	/vmlinuz-7.0.0-1026-nvidia root=UUID=$U ro quiet splash
	}
}
EOF
eq "linux line of ours" "		linux	/vmlinuz-7.3.0-n1x1 root=UUID=$U ro quiet splash $P \$vt_handoff" \
	"$(grub_linux_args "$T/linux.cfg" 7.3.0-n1x1)"
eq "linux line of 1026, not its -64k sibling" "		linux	/vmlinuz-7.0.0-1026-nvidia root=UUID=$U ro quiet splash" \
	"$(grub_linux_args "$T/linux.cfg" 7.0.0-1026-nvidia)"
fails "linux line of a missing kernel" grub_linux_args "$T/linux.cfg" 7.0.0-44-generic
eq "grub.cfg has our options" 0 "$(cmdline_has_pci "$(grub_linux_args "$T/linux.cfg" 7.3.0-n1x1)"; echo $?)"
eq "grub.cfg lacks our options" 1 "$(cmdline_has_pci "$(grub_linux_args "$T/linux.cfg" 7.0.0-1026-nvidia)"; echo $?)"
eq "has pci split over two pci=" 0 "$(cmdline_has_pci "pci=hpbussize=0x80 x pci=realloc,hpmmiosize=32M,hpmmioprefsize=32G"; echo $?)"
eq "has pci with another value" 1 "$(cmdline_has_pci "pci=hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=64G"; echo $?)"
eq "has pci of nothing" 1 "$(cmdline_has_pci ""; echo $?)"

# --- grub.cfg without the submenu (GRUB_DISABLE_SUBMENU=y) ------------------------------------
cat >"$T/flat.cfg" <<EOF
function load_video {
	insmod all_video
}
menuentry 'Ubuntu' --class ubuntu \$menuentry_id_option 'gnulinux-simple-$U' {
}
menuentry 'Ubuntu, with Linux 7.3.0-n1x1' --class ubuntu \$menuentry_id_option 'gnulinux-7.3.0-n1x1-advanced-$U' {
}
menuentry 'Ubuntu, with Linux 7.0.0-1026-nvidia' --class ubuntu \$menuentry_id_option 'gnulinux-7.0.0-1026-nvidia-advanced-$U' {
}
EOF
eq "flat entry for ours" "gnulinux-7.3.0-n1x1-advanced-$U" "$(grub_entry_id "$T/flat.cfg" 7.3.0-n1x1)"
eq "flat entry for 1026" "gnulinux-7.0.0-1026-nvidia-advanced-$U" "$(grub_entry_id "$T/flat.cfg" 7.0.0-1026-nvidia)"
cat >"$T/after.cfg" <<EOF
submenu 'Advanced options for Ubuntu' \$menuentry_id_option 'gnulinux-advanced-$U' {
	menuentry 'Ubuntu, with Linux 7.0.0-1026-nvidia' \$menuentry_id_option 'gnulinux-7.0.0-1026-nvidia-advanced-$U' {
	}
}
menuentry 'Ubuntu, with Linux 7.3.0-n1x1' \$menuentry_id_option 'gnulinux-7.3.0-n1x1-advanced-$U' {
}
EOF
eq "entry after the submenu has no submenu id" "gnulinux-7.3.0-n1x1-advanced-$U" "$(grub_entry_id "$T/after.cfg" 7.3.0-n1x1)"
eq "entry in the submenu before it" "gnulinux-advanced-$U>gnulinux-7.0.0-1026-nvidia-advanced-$U" \
	"$(grub_entry_id "$T/after.cfg" 7.0.0-1026-nvidia)"
