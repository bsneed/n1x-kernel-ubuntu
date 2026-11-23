# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib.sh's apply_patch, which scripts/build.sh and scripts/nvidia-dkms.sh use.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash

mkdir -p "$T/ptree/src"
printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"
cat >"$T/fix.patch" <<'PATCH'
--- a/src/f.c
+++ b/src/f.c
@@ -1,3 +1,3 @@
 one
-two
+TWO
 three
PATCH
eq "patch applies" "0 one TWO three" "$(apply_patch "$T/ptree" "$T/fix.patch" >/dev/null 2>&1; echo $?) $(paste -sd' ' "$T/ptree/src/f.c")"
# An already-applied patch (merged upstream) must fail the build, not be reverted (GNU patch
# --batch alone assumes -R and exits 0).
fails "patch already applied fails" apply_patch "$T/ptree" "$T/fix.patch"
eq "patch already applied is not reverted" "one TWO three" "$(paste -sd' ' "$T/ptree/src/f.c")"
printf 'one\nzwei\nthree\n' >"$T/ptree/src/f.c"
fails "patch that does not fit fails" apply_patch "$T/ptree" "$T/fix.patch"
eq "patch that does not fit leaves the file" "one zwei three" "$(paste -sd' ' "$T/ptree/src/f.c")"
printf 'zero\none\ntwo\nthree\n' >"$T/ptree/src/f.c"
cat >"$T/fuzz.patch" <<'PATCH'
--- a/src/f.c
+++ b/src/f.c
@@ -1,3 +1,3 @@
 one
-two
+TWO
 four
PATCH
fails "patch needing fuzz fails" apply_patch "$T/ptree" "$T/fuzz.patch"
fails "patch in a missing tree fails" apply_patch "$T/nope" "$T/fix.patch"

# --- apply_patch_dir: build.sh applies patches/ubuntu with it -------------------------------
printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"
mkdir -p "$T/pdir" "$T/pempty"
cp "$T/fix.patch" "$T/pdir/0001-fix.patch"
cat >"$T/pdir/0002-on-top.patch" <<'PATCH'
--- a/src/f.c
+++ b/src/f.c
@@ -1,3 +1,3 @@
 one
-TWO
+2
 three
PATCH
printf 'not a patch\n' >"$T/pdir/README.md"
eq "patch dir: applied in name order, others ignored" "applied 0001-fix.patch applied 0002-on-top.patch|one 2 three" \
	"$(apply_patch_dir "$T/ptree" "$T/pdir" | paste -sd' ' -)|$(paste -sd' ' "$T/ptree/src/f.c")"
eq "patch dir without patches" "0 " "$(apply_patch_dir "$T/ptree" "$T/pempty"; echo "$? $(apply_patch_dir "$T/ptree" "$T/pempty")")"
fails "patch dir missing" apply_patch_dir "$T/ptree" "$T/nope"
printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"
cp "$T/fix.patch" "$T/pdir/0003-again.patch"
fails "patch dir with a patch that does not apply" apply_patch_dir "$T/ptree" "$T/pdir"
eq "patch dir: the failing patch is named" "0003-again.patch does not apply (already applied upstream, or no longer fits)" \
	"$(printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"; apply_patch_dir "$T/ptree" "$T/pdir" 2>&1 >/dev/null)"

# --- patches/ubuntu --------------------------------------------------------------------------
for p in patches/ubuntu/*.patch; do
	[[ -f $p ]] || continue
	n=${p##*/}
	eq "$n: named NNNN-short-description.patch" 1 "$([[ $n =~ ^[0-9]{4}-[a-z0-9-]+\.patch$ ]] && echo 1)"
	eq "$n: git-format header" 1 "$(sed -n 1p "$p" | grep -c '^From [0-9a-f]\{40\} ')"
	eq "$n: says when to drop it" 1 "$(grep -c '^Drop it when ' "$p")"
done

# 0001, the mt7925 reset-panic fix, on the 7.3 source it patches (tests/fixtures/linux-7.3 holds
# excerpts of the two files, which Omarchy's patches do not touch).
M=patches/ubuntu/0001-mt7925-fix-reset-panic-caused-by-the-wm2-rx-irq-mask.patch
K=$T/linux-7.3
MT=$K/drivers/net/wireless/mediatek/mt76/mt7925
cp -R tests/fixtures/linux-7.3 "$K"
eq "0001: upstream commit" 1 "$(grep -c '^n1x-kernel-ubuntu: upstream commit c182bfe944eb275f7526cc326f81229b0e974a0c$' "$M")"
eq "0001: in 7.3.2, and its CVE" 2 "$(grep -c -e 'in 7\.3\.2 as 3c287de98388c3746d8b884de9fd8c3e83f41c04' -e 'CVE-2026-99560' "$M")"
eq "0001: dropped at 7.3.2" 1 "$(grep -c 'is >= 7\.3\.2' "$M")"
irq_map() { sed -n '/^static const struct mt792x_irq_map mt7925_irq_map = {$/,/^};$/p' "$MT/pci.c"; }
eq "0001 fixture: 7.3's mt7925_irq_map sets the WM2 mask" 1 "$(irq_map | grep -c wm2_complete_mask)"
eq "0001 applies to 7.3" 0 "$(apply_patch "$K" "$M" >/dev/null 2>&1; echo $?)"
eq "0001: mt7925_irq_map has no WM2 mask" 0 "$(irq_map | grep -c wm2_complete_mask)"
eq "0001: mt7925_irq_map keeps its other masks" 3 "$(irq_map | grep -c -e '\.all_complete_mask = MT7925_' -e '\.data_complete_mask' -e '\.wm_complete_mask')"
eq "0001: MT7925_INT_RX_DONE_ALL without WM2" \
	'#define MT7925_INT_RX_DONE_ALL (MT7925_INT_RX_DONE_DATA | \ MT7925_INT_RX_DONE_WM)' \
	"$(sed -n '/^#define MT7925_INT_RX_DONE_ALL/,/)$/p' "$MT/regs.h" | paste -sd' ' - | tr -s '\t ' ' ')"
eq "0001: MT7927 and MT7928 keep their WM2 masks" 2 "$(grep -c '\.wm2_complete_mask = ' "$MT/pci.c")"
cp -R "$MT" "$T/mt7925-fixed"
fails "0001 on a tree that has it (7.3.2) fails the build" apply_patch "$K" "$M"
# (patch leaves its .rej files; the build stops there anyway)
eq "0001 on a tree that has it is not reverted" "" "$(diff -r -x '*.rej' "$T/mt7925-fixed" "$MT")"
unset -f irq_map

# 0002, the i2c-hid quirk for the ProArt P16, on excerpts of i2c-hid-core.c (which Omarchy's
# patches leave alone).
Q=patches/ubuntu/0002-hid-i2c-hid-no-sleep-on-shutdown-on-the-asus-proart-p16.patch
C=$K/drivers/hid/i2c-hid/i2c-hid-core.c
eq "0002: not upstream" 1 "$(grep -c '^n1x-kernel-ubuntu: not upstream\.' "$Q")"
eq "0002: why we carry it" 1 "$(grep -c '^Why we carry it: ' "$Q")"
eq "0002: the test matrix" 4 "$(grep -c -e '^- stock i2c-hid, probed late' -e '^- stock i2c-hid, probed early' \
	-e '^- no SET_POWER(SLEEP) in i2c_hid_core_shutdown(), probed late' -e '^- no SET_POWER(SLEEP) at shutdown, probed early' "$Q")"
eq "0002: says why it is per machine" 1 "$(grep -c '^first version of this patch (7\.3\.0-n1x3) skipped it only for the$' "$Q")"
fn() { sed -n "/^$1/,/^}\(;\)\?\$/p" "$C"; } # fn START: the function or table starting with START
eq "0002 fixture: shutdown puts every device to sleep" "	i2c_hid_set_power(ihid, I2C_HID_PWR_SLEEP);" \
	"$(fn 'void i2c_hid_core_shutdown(' | grep -F 'i2c_hid_set_power(')"
suspend_was=$(fn 'static int i2c_hid_core_suspend(') quirks_was=$(fn '} i2c_hid_quirks\[\] = {')
eq "0002 applies after Omarchy" 0 "$(apply_patch "$K" "$Q" >/dev/null 2>&1; echo $?)"
eq "0002: the quirk is the next free bit" "#define I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN	BIT(8)" \
	"$(grep -F 'I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN	' "$C" | head -1)"
eq "0002: BIT(8) was free" 1 "$(grep -c 'BIT(8)' "$C")"
eq "0002: shutdown skips SET_POWER(SLEEP) with the quirk" \
	"if (!(ihid->quirks & I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN)) i2c_hid_set_power(ihid, I2C_HID_PWR_SLEEP);" \
	"$(fn 'void i2c_hid_core_shutdown(' | grep -A1 -F 'I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN' | paste -sd' ' - | tr -s '\t ' ' ' | sed 's/^ //')"
eq "0002: shutdown still frees the IRQ and runs shutdown_tail" 2 \
	"$(fn 'void i2c_hid_core_shutdown(' | grep -c -e '^	free_irq(client->irq, ihid);$' -e '^	i2c_hid_core_shutdown_tail(ihid);$')"
eq "0002: suspend is unchanged" "$suspend_was" "$(fn 'static int i2c_hid_core_suspend(')"
eq "0002: the per-device quirk table is unchanged" "$quirks_was" "$(fn '} i2c_hid_quirks\[\] = {')"
eq "0002: the quirk is tested only at shutdown" 1 "$(grep -c 'quirks & I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN' "$C")"
eq "0002: the DMI table matches the P16 H7607BA" \
	'.ident = "ASUS ProArt P16 H7607BA",|DMI_MATCH(DMI_SYS_VENDOR, "ASUS"),|DMI_MATCH(DMI_PRODUCT_NAME, "H7607BA"),|{ }' \
	"$(fn 'static const struct dmi_system_id i2c_hid_no_sleep_on_shutdown_dmi' | grep -e ident -e DMI_MATCH -e '{ }' | tr -d '\t' | paste -sd'|' -)"
eq "0002: the ident is check.sh's" 1 "$(grep -cF ".ident = \"$(. scripts/lib-initramfs.sh; echo "$I2C_HID_QUIRK_IDENT")\"," "$C")"
eq "0002: every device on the P16 gets the quirk, after the per-device ones" \
	"ihid->quirks = i2c_hid_lookup_quirk(hid->vendor, hid->product); if (dmi_check_system(i2c_hid_no_sleep_on_shutdown_dmi)) ihid->quirks |= I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN;" \
	"$(grep -A2 -F 'ihid->quirks = i2c_hid_lookup_quirk(' "$C" | paste -sd' ' - | tr -s '\t ' ' ' | sed 's/^ //')"
eq "0002: includes linux/dmi.h" 1 "$(grep -c '^#include <linux/dmi.h>$' "$C")"
cp "$C" "$T/core-fixed.c"
fails "0002 on a tree that has it fails the build" apply_patch "$K" "$Q"
eq "0002 on a tree that has it is not reverted" "" "$(diff "$T/core-fixed.c" "$C")"
unset -f fn
unset suspend_was quirks_was
