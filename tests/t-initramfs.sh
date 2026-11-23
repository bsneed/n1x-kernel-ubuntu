# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib-initramfs.sh (the ProArt P16's early i2c-hid load, the i2c-hid quirk check) and of
# lib-steps.sh's early_load_apply and early_load_drop, with fake files and a stand-in dpkg-query.
# Sourced by tests/run.sh, which defines eq, fails, skip and $T.
# shellcheck shell=bash
. scripts/lib-initramfs.sh
. scripts/lib-steps.sh
DMI_PRODUCT=$T/ir-product EARLY_DRACUT=$T/ir-etc/dracut.conf.d/50-i2c-hid-early.conf
EARLY_ITOOLS=$T/ir-etc/initramfs-tools/modules

# --- which machine, which tool ----------------------------------------------------------------
echo 'ProArt P16 H7607BA' >"$DMI_PRODUCT"
eq "P16: the H7607BA" 0 "$(is_proart_p16; echo $?)"
echo 'Zenbook A14 UX3407QA' >"$DMI_PRODUCT"
eq "P16: not another laptop" 1 "$(is_proart_p16; echo $?)"
eq "P16: not without DMI" 1 "$(DMI_PRODUCT=$T/none is_proart_p16; echo $?)"
# shellcheck disable=SC2317,SC2329 # called by initramfs_tool (SC2317 before shellcheck 0.10)
dpkg-query() { # dpkg-query -W -f FORMAT PACKAGE: the status from $T/ir-dpkg ("ii dracut" lines)
	awk -v p="$4" '$2 == p {print $1; f = 1} END {exit !f}' "$T/ir-dpkg"
}
printf 'ii dracut\nun initramfs-tools\n' >"$T/ir-dpkg"
eq "tool: dracut (26.04)" dracut "$(initramfs_tool)"
printf 'un dracut\nii initramfs-tools\n' >"$T/ir-dpkg"
eq "tool: initramfs-tools" initramfs-tools "$(initramfs_tool)"
printf 'rc dracut\nii initramfs-tools\n' >"$T/ir-dpkg"
eq "tool: a removed dracut doesn't count" initramfs-tools "$(initramfs_tool)"
printf 'rc dracut\n' >"$T/ir-dpkg"
fails "tool: neither" initramfs_tool

# --- the dracut drop-in -------------------------------------------------------------------------
early_dracut_text >"$T/ir-ours"
eq "dracut: forces the three drivers" 'force_drivers+=" i2c_mt65xx i2c_hid i2c_hid_acpi "' "$(early_settings "$T/ir-ours")"
eq "dracut: says what it is" "$EARLY_MARK (scripts/install.sh): load the ProArt P16's i2c-hid drivers early," "$(head -1 "$T/ir-ours")"
eq "dracut: says how to remove it" 1 "$(grep -c "^# scripts/install.sh --remove deletes this. Remove by hand: sudo rm $EARLY_DRACUT;" "$T/ir-ours")"
eq "dracut: ours is ours" 0 "$(early_dracut_is_ours "$T/ir-ours"; echo $?)"
eq "dracut: a missing file is not ours" 1 "$(early_dracut_is_ours "$T/none"; echo $?)"
# The hand-written one rtx24 was tested with (2026-11-22).
cat >"$T/ir-rtx24" <<'CONF'
# rtx24: load the i2c-hid drivers early in the initramfs. With touchpad firmware V1.26.0918.1
# the keyboard/touchpad die on a warm reboot if they are probed late (~3 s).
force_drivers+=" i2c_mt65xx i2c_hid i2c_hid_acpi "
CONF
eq "dracut: rtx24's hand-written one is not ours" 1 "$(early_dracut_is_ours "$T/ir-rtx24"; echo $?)"
eq "dracut: but install.sh may take it over" 0 "$(early_dracut_adoptable "$T/ir-rtx24"; echo $?)"
eq "dracut: may write a missing one" 0 "$(early_dracut_adoptable "$T/none"; echo $?)"
eq "dracut: may rewrite ours" 0 "$(early_dracut_adoptable "$T/ir-ours"; echo $?)"
printf 'force_drivers+=" i2c_hid "\n' >"$T/ir-other"
eq "dracut: not one with other settings" 1 "$(early_dracut_adoptable "$T/ir-other"; echo $?)"
{ cat "$T/ir-rtx24"; echo 'add_drivers+=" foo "'; } >"$T/ir-more"
eq "dracut: not one that sets more" 1 "$(early_dracut_adoptable "$T/ir-more"; echo $?)"
mkdir -p "$T/ir-dir"
eq "dracut: not a directory" 1 "$(early_dracut_adoptable "$T/ir-dir"; echo $?)"

# --- the initramfs-tools block -------------------------------------------------------------------
printf '# List of modules\n# raid1\nsd_mod\n' >"$T/ir-modules"
early_itools_with "$T/ir-modules" >"$T/ir-modules.1"
eq "itools: block after the file" "# List of modules|# raid1|sd_mod|$EARLY_BEGIN|i2c_mt65xx|i2c_hid|i2c_hid_acpi|$EARLY_END" \
	"$(paste -sd'|' "$T/ir-modules.1")"
eq "itools: twice is once" "$(cat "$T/ir-modules.1")" "$(early_itools_with "$T/ir-modules.1")"
eq "itools: without it, the file as it was" "$(cat "$T/ir-modules")" "$(early_itools_without "$T/ir-modules.1")"
{ cat "$T/ir-modules.1"; echo usbhid; } >"$T/ir-modules.2"
eq "itools: lines after the block stay" "# List of modules|# raid1|sd_mod|usbhid" "$(early_itools_without "$T/ir-modules.2" | paste -sd'|' -)"
eq "itools: a missing file" "$EARLY_BEGIN|i2c_mt65xx|i2c_hid|i2c_hid_acpi|$EARLY_END" "$(early_itools_with "$T/none" | paste -sd'|' -)"
eq "itools: a missing file without it" "" "$(early_itools_without "$T/none")"

# --- check.sh: what an initramfs lacks ----------------------------------------------------------------
# lsinitrd lines from rtx24's 7.3.0-n1x2 initramfs (dracut 110), and the rd.driver.pre lines of its
# etc/cmdline.d/20-force_drivers.conf.
cat >"$T/ir-list" <<'LIST'
-rw-r--r--   1 root     root        12537 Nov 21 18:46 usr/lib/modules/7.3.0-n1x2/kernel/drivers/hid/i2c-hid/i2c-hid-acpi.ko
-rw-r--r--   1 root     root        12409 Nov 21 18:46 usr/lib/modules/7.3.0-n1x2/kernel/drivers/hid/i2c-hid/i2c-hid-acpi-prp0001.ko
-rw-r--r--   1 root     root        62041 Nov 21 18:46 usr/lib/modules/7.3.0-n1x2/kernel/drivers/hid/i2c-hid/i2c-hid.ko
-rw-r--r--   1 root     root        71825 Nov 21 18:46 usr/lib/modules/7.3.0-n1x2/kernel/drivers/i2c/busses/i2c-mt65xx.ko
LIST
printf 'rd.driver.pre=i2c_mt65xx\nrd.driver.pre=i2c_hid\nrd.driver.pre=i2c_hid_acpi\n' >"$T/ir-pre"
eq "initramfs: has it all" "" "$(early_load_missing "$T/ir-list" "$T/ir-pre")"
eq "initramfs: one comma list" "" "$(early_load_missing "$T/ir-list" <(echo 'rd.driver.pre=i2c_mt65xx,i2c_hid,i2c_hid_acpi'))"
eq "initramfs: initramfs-tools' conf/modules, compressed modules" "" \
	"$(early_load_missing <(sed 's/\.ko$/.ko.zst/; s/^.* //' "$T/ir-list") <(printf 'i2c_mt65xx\ni2c_hid\ni2c_hid_acpi\n'))"
eq "initramfs: nothing loaded first" "i2c_mt65xx not loaded first|i2c_hid not loaded first|i2c_hid_acpi not loaded first" \
	"$(early_load_missing "$T/ir-list" /dev/null | paste -sd'|' -)"
eq "initramfs: no i2c-hid.ko (i2c-hid-acpi.ko is another module)" "no i2c-hid.ko" \
	"$(early_load_missing <(grep -v '/i2c-hid\.ko$' "$T/ir-list") "$T/ir-pre")"
eq "initramfs: a module in updates/ is not the kernel's" "no i2c-hid.ko" \
	"$(early_load_missing <(sed 's|kernel/drivers/hid/i2c-hid/i2c-hid\.ko|updates/i2chid-test/i2c-hid.ko|' "$T/ir-list") "$T/ir-pre")"
eq "initramfs: no I2C controller" "no i2c-mt65xx.ko|i2c_mt65xx not loaded first" \
	"$(early_load_missing <(grep -v mt65xx "$T/ir-list") <(grep -v mt65xx "$T/ir-pre") | paste -sd'|' -)"
eq "initramfs: a module name inside another doesn't count" "i2c_hid not loaded first" \
	"$(early_load_missing "$T/ir-list" <(printf 'rd.driver.pre=i2c_mt65xx\nrd.driver.pre=i2c_hid_acpi\n'))"

# --- check.sh: the quirk in i2c-hid.ko --------------------------------------------------------
qko() { # qko FILE ENTRY...: a fake module holding the ENTRYs (printf escapes) among other bytes
	local f=$1 e
	shift
	{ printf 'ELF\0\0junk'; for e in "$@"; do printf '%b\0\0\0\0' "$e"; done; printf 'tail'; } >"$f"
}
qko "$T/ir-q.ko" "${I2C_HID_QUIRK_ENTRIES[@]}"
eq "quirk: all three entries" 0 "$(i2c_hid_has_quirk "$T/ir-q.ko"; echo $?)"
qko "$T/ir-q2.ko" "${I2C_HID_QUIRK_ENTRIES[@]:0:2}"
eq "quirk: not without the touchpad's" 1 "$(i2c_hid_has_quirk "$T/ir-q2.ko"; echo $?)"
qko "$T/ir-q3.ko" '\x05\x0b\x42\x4b\x00\x00\x00\x00' "${I2C_HID_QUIRK_ENTRIES[@]:1}"
eq "quirk: not with another quirk bit" 1 "$(i2c_hid_has_quirk "$T/ir-q3.ko"; echo $?)"
eq "quirk: not without a file" 1 "$(i2c_hid_has_quirk "$T/none.ko"; echo $?)"
eq "quirk: not without a path (modinfo found none)" 1 "$(i2c_hid_has_quirk ""; echo $?)"
for z in zstd xz; do
	if command -v "$z" >/dev/null; then
		"$z" -q -k -c "$T/ir-q.ko" >"$T/ir-q.ko.${z/zstd/zst}"
		eq "quirk: a $z-compressed module" 0 "$(i2c_hid_has_quirk "$T/ir-q.ko.${z/zstd/zst}"; echo $?)"
		"$z" -q -k -c "$T/ir-q2.ko" >"$T/ir-q2.ko.${z/zstd/zst}"
		eq "quirk: a $z-compressed module without it" 1 "$(i2c_hid_has_quirk "$T/ir-q2.ko.${z/zstd/zst}"; echo $?)"
	else
		skip "quirk: a $z-compressed module" "no $z"
	fi
done
echo garbage >"$T/ir-bad.ko.xz"
eq "quirk: a module that doesn't decompress" 1 "$(i2c_hid_has_quirk "$T/ir-bad.ko.xz"; echo $?)"

# --- install.sh's steps ---------------------------------------------------------------------------
TMP=$T/ir-tmp
mkdir -p "$TMP"
er() { ("$@") >"$T/ir-out" 2>"$T/ir-err"; echo "$?"; } # er STEP: its status; output in ir-out/ir-err
state() { # what is in the fake /etc: the drop-in's settings, our block's modules
	printf 'dracut:%s itools:%s' "$(if [[ -f $EARLY_DRACUT ]]; then early_settings "$EARLY_DRACUT"; else echo -; fi)" \
		"$(awk -v b="$EARLY_BEGIN" -v e="$EARLY_END" '$0 == e {f = 0} f; $0 == b {f = 1}' "$EARLY_ITOOLS" 2>/dev/null | paste -sd, -)"
}
F='force_drivers+=" i2c_mt65xx i2c_hid i2c_hid_acpi "'
echo 'ProArt P16 H7607BA' >"$DMI_PRODUCT"
printf 'ii dracut\n' >"$T/ir-dpkg"
eq "apply: dracut, a new drop-in" "0|dracut:$F itools:" "$(er early_load_apply)|$(state)"
eq "apply: says so" "==> Wrote $EARLY_DRACUT: the i2c-hid drivers load early (i2c_mt65xx i2c_hid i2c_hid_acpi)" "$(cat "$T/ir-out")"
eq "apply: the drop-in is ours, mode 644" "0 644" "$(early_dracut_is_ours "$EARLY_DRACUT"; echo "$? $(stat -c %a "$EARLY_DRACUT" 2>/dev/null || stat -f %Lp "$EARLY_DRACUT")")"
eq "apply: a second run changes nothing, quietly" "0|dracut:$F itools:|" "$(er early_load_apply)|$(state)|$(cat "$T/ir-out" "$T/ir-err")"
cp "$T/ir-rtx24" "$EARLY_DRACUT"
eq "apply: takes over rtx24's hand-written one" "0|dracut:$F itools:|0" "$(er early_load_apply)|$(state)|$(early_dracut_is_ours "$EARLY_DRACUT"; echo $?)"
ls "$(dirname "$EARLY_DRACUT")" >"$T/ir-ls"
eq "apply: and leaves no second file" "50-i2c-hid-early.conf" "$(cat "$T/ir-ls")"
cp "$T/ir-other" "$EARLY_DRACUT"
eq "apply: someone else's with other settings stays" "0|$(cat "$T/ir-other")" "$(er early_load_apply)|$(cat "$EARLY_DRACUT")"
eq "apply: and says why" 1 "$(grep -c "^WARNING: $EARLY_DRACUT was not written by install.sh and sets something else, so it stays as it is" "$T/ir-err")"
eq "drop: leaves someone else's" "0|$(cat "$T/ir-other")" "$(er early_load_drop)|$(cat "$EARLY_DRACUT")"
rm "$EARLY_DRACUT"
printf 'ii initramfs-tools\n' >"$T/ir-dpkg"
mkdir -p "$(dirname "$EARLY_ITOOLS")"
cp "$T/ir-modules" "$EARLY_ITOOLS"
eq "apply: initramfs-tools, our block" "0|dracut:- itools:i2c_mt65xx,i2c_hid,i2c_hid_acpi" "$(er early_load_apply)|$(state)"
eq "apply: initramfs-tools, the rest of the list stays" "$(cat "$T/ir-modules")" "$(early_itools_without "$EARLY_ITOOLS")"
eq "apply: initramfs-tools, a second run changes nothing" "0|" "$(er early_load_apply)|$(cat "$T/ir-out")"
printf 'ii dracut\n' >"$T/ir-dpkg"
eq "apply: moved to dracut, the block goes" "0|dracut:$F itools:" "$(er early_load_apply)|$(state)"
eq "apply: moved to dracut, the list is as it was" "$(cat "$T/ir-modules")" "$(cat "$EARLY_ITOOLS")"
printf 'ii initramfs-tools\n' >"$T/ir-dpkg"
eq "apply: moved to initramfs-tools, our drop-in goes" "0|dracut:- itools:i2c_mt65xx,i2c_hid,i2c_hid_acpi" "$(er early_load_apply)|$(state)"
printf 'ii dracut\n' >"$T/ir-dpkg"
er early_load_apply >/dev/null
cp "$T/ir-modules.1" "$EARLY_ITOOLS"
eq "drop: removes both" "0|dracut:- itools:" "$(er early_load_drop)|$(state)"
eq "drop: the list is as it was" "$(cat "$T/ir-modules")" "$(cat "$EARLY_ITOOLS")"
eq "drop: twice is fine, quietly" "0|dracut:- itools:|" "$(er early_load_drop)|$(state)|$(cat "$T/ir-out" "$T/ir-err")"
er early_load_apply >/dev/null
echo 'Zenbook A14 UX3407QA' >"$DMI_PRODUCT"
eq "apply: not a P16, ours goes" "0|dracut:- itools:" "$(er early_load_apply)|$(state)"
cp "$T/ir-rtx24" "$EARLY_DRACUT"
eq "apply: not a P16, a hand-written one stays" "0|dracut:$F itools:" "$(er early_load_apply)|$(state)"
rm "$EARLY_DRACUT"
echo 'ProArt P16 H7607BA' >"$DMI_PRODUCT"
printf 'rc dracut\n' >"$T/ir-dpkg"
eq "apply: neither tool, nothing written" "0|dracut:- itools:" "$(er early_load_apply)|$(state)"
eq "apply: neither tool, says so" 1 "$(grep -c '^WARNING: neither dracut nor initramfs-tools is installed' "$T/ir-err")"
unset -f dpkg-query qko er state
unset F TMP
