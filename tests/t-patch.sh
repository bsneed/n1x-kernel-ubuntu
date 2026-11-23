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

# 0002, i2c-hid's probe retry on the ProArt P16, on 7.3's i2c-hid-core.c (the whole file, which
# Omarchy's patches leave alone).
Q=patches/ubuntu/0002-hid-i2c-hid-retry-a-failed-probe-on-the-asus-proart-p16.patch
C=$K/drivers/hid/i2c-hid/i2c-hid-core.c
eq "0002 fixture: 7.3's i2c-hid-core.c" bd907b7a8d836c30559851ce339cb00df69cd817e163a6c5c901dc7774538e87 \
	"$(sha256_of tests/fixtures/linux-7.3/drivers/hid/i2c-hid/i2c-hid-core.c)"
eq "0002: not upstream" 1 "$(grep -c '^n1x-kernel-ubuntu: not upstream\.' "$Q")"
eq "0002: why we carry it" 1 "$(grep -c '^Why we carry it: ' "$Q")"
eq "0002: names the four devices" 4 "$(grep -c -e 'i2c-MKB0001, 0B05:4B42' -e 'i2c-313030304B544C49, 222A:5554' \
	-e 'i2c-ASTH0001, 0B05:4543' -e 'i2c-3030443150435341, 093A:4F01' "$Q")"
eq "0002: the evidence" 2 "$(grep -c -e '^The devices are slow, not dead' -e 'INTR_STAT 0, nothing$' "$Q")"
eq "0002: signed off" 1 "$(grep -c '^Signed-off-by: Brandon Sneed <brandon@redf.net>$' "$Q")"
eq "0002: touches only i2c-hid-core.c" "drivers/hid/i2c-hid/i2c-hid-core.c" "$(sed -n 's|^+++ b/||p' "$Q")"
fn() { sed -n "/^$1/,/^}\(;\)\?\$/p" "$C"; } # fn START: the function or table starting with START
quirks_was=$(fn '} i2c_hid_quirks\[\] = {') start_was=$(fn 'static int i2c_hid_start_hwreset(')
suspend_was=$(fn 'static int i2c_hid_core_suspend(') resume_was=$(fn 'static int i2c_hid_core_resume(')
parse_was=$(fn 'static int i2c_hid_parse(') register_was=$(fn 'static int i2c_hid_core_register_hid(')
# What tests/i2c-hid-retry fakes as stock, and the pm ops table
stock() {
	local f
	for f in 'static int i2c_hid_xfer(' 'static int i2c_hid_read_register(' 'static int i2c_hid_set_power(' \
		'static void i2c_hid_free_buffers(' 'static int i2c_hid_alloc_buffers(' 'static u32 i2c_hid_lookup_quirk(' \
		'static int i2c_hid_core_register_panel_follower(' 'const struct dev_pm_ops i2c_hid_core_pm = {'; do
		fn "$f"
	done
}
stock_was=$(stock)
eq "0002 fixture: no probe retry yet" 0 "$(grep -c probe_retry "$C")"
eq "0002 applies after Omarchy and 0001" 0 "$(apply_patch "$K" "$Q" >/dev/null 2>&1; echo $?)"
eq "0002: the DMI table holds only the P16 H7607BA" \
	'.ident = "ASUS ProArt P16 H7607BA",|DMI_MATCH(DMI_SYS_VENDOR, "ASUS"),|DMI_MATCH(DMI_PRODUCT_NAME, "H7607BA"),|{ }' \
	"$(fn 'static const struct dmi_system_id i2c_hid_probe_retry_dmi' | grep -e ident -e DMI_MATCH -e '{ }' | tr -d '\t' | paste -sd'|' -)"
eq "0002: includes linux/dmi.h" 1 "$(grep -c '^#include <linux/dmi.h>$' "$C")"
eq "0002: every 5 s for up to 300 s" "5000 300000" \
	"$(sed -n 's/^#define I2C_HID_PROBE_RETRY_\(INTERVAL\|TIMEOUT\)_MS\t*\([0-9]*\)$/\2/p' "$C" | paste -sd' ' -)"
eq "0002: includes linux/workqueue.h" 1 "$(grep -c '^#include <linux/workqueue.h>$' "$C")"
# What the retry does (which machines and errors, the timing, remove, shutdown and system sleep in
# every state) is tested by running it: tests/t-i2c-hid-retry.sh. What follows here is what that
# can't see: the dev_pm_ops table, and the stock code 0002 must leave alone.
eq "0002: the pm ops, and what the retry harness fakes, are unchanged" "$stock_was" "$(stock)"
eq "0002: ... and that is 8 blocks" 8 "$(stock | grep -c '^}')"
eq "0002: the quirk table is unchanged" "$quirks_was" "$(fn '} i2c_hid_quirks\[\] = {')"
eq "0002: the reset handshake is unchanged" "$start_was" "$(fn 'static int i2c_hid_start_hwreset(')"
eq "0002: parse is unchanged" "$parse_was" "$(fn 'static int i2c_hid_parse(')"
eq "0002: register_hid is unchanged" "$register_was" "$(fn 'static int i2c_hid_core_register_hid(')"
eq "0002: core suspend is unchanged" "$suspend_was" "$(fn 'static int i2c_hid_core_suspend(')"
eq "0002: core resume is unchanged" "$resume_was" "$(fn 'static int i2c_hid_core_resume(')"
cp "$C" "$T/core-retry.c"
fails "0002 on a tree that has it fails the build" apply_patch "$K" "$Q"
eq "0002 on a tree that has it is not reverted" "" "$(diff "$T/core-retry.c" "$C")"
unset -f fn stock
unset Q C stock_was quirks_was start_was suspend_was resume_was parse_was register_was
