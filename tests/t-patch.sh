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
flat() { paste -sd' ' - | tr -s '\t ' ' ' | sed 's/^ //'; }
quirks_was=$(fn '} i2c_hid_quirks\[\] = {') start_was=$(fn 'static int i2c_hid_start_hwreset(')
suspend_was=$(fn 'static int i2c_hid_core_suspend(') resume_was=$(fn 'static int i2c_hid_core_resume(')
parse_was=$(fn 'static int i2c_hid_parse(') register_was=$(fn 'static int i2c_hid_core_register_hid(')
eq "0002 fixture: no probe retry yet" 0 "$(grep -c probe_retry "$C")"
eq "0002 applies after Omarchy and 0001" 0 "$(apply_patch "$K" "$Q" >/dev/null 2>&1; echo $?)"
eq "0002: the DMI table holds only the P16 H7607BA" \
	'.ident = "ASUS ProArt P16 H7607BA",|DMI_MATCH(DMI_SYS_VENDOR, "ASUS"),|DMI_MATCH(DMI_PRODUCT_NAME, "H7607BA"),|{ }' \
	"$(fn 'static const struct dmi_system_id i2c_hid_probe_retry_dmi' | grep -e ident -e DMI_MATCH -e '{ }' | tr -d '\t' | paste -sd'|' -)"
eq "0002: includes linux/dmi.h" 1 "$(grep -c '^#include <linux/dmi.h>$' "$C")"
eq "0002: every 5 s for up to 120 s" "5000 120000" \
	"$(sed -n 's/^#define I2C_HID_PROBE_RETRY_\(INTERVAL\|TIMEOUT\)_MS\t*\([0-9]*\)$/\2/p' "$C" | paste -sd' ' -)"
eq "0002: retries -ETIMEDOUT and -ENXIO, on those machines only" \
	"return ihid->probe_retry && (error == -ETIMEDOUT || error == -ENXIO);" \
	"$(fn 'static bool i2c_hid_probe_retryable(' | grep return | flat)"
eq "0002: never for a panel follower" "ihid->probe_retry = !ihid->is_panel_follower && dmi_check_system(i2c_hid_probe_retry_dmi);" \
	"$(grep -A1 -F 'ihid->probe_retry = ' "$C" | flat)"
eq "0002: the descriptor fetch keeps -ENODEV unless it retries" \
	"return i2c_hid_probe_retryable(ihid, error) ? error : -ENODEV;" \
	"$(fn 'static int i2c_hid_fetch_hid_descriptor(' | grep -F 'i2c_hid_probe_retryable(' | flat)"
eq "0002: probe defers only a hid it did not add, past the IRQ and power-down" \
	"err_free_irq: free_irq(client->irq, ihid); err_power_down: if (!ihid->is_panel_follower) i2c_hid_core_power_down(ihid); err_destroy_device: if (!(hid->status & HID_STAT_ADDED) && i2c_hid_probe_retryable(ihid, ret)) return i2c_hid_probe_retry_start(ihid, ret); hid_destroy_device(hid);" \
	"$(fn 'int i2c_hid_core_probe(' | sed -n '/^err_free_irq:$/,/hid_destroy_device/p' | flat)"
eq "0002: deferring returns 0 after queueing the work" \
	"ihid->probe_retry_start = jiffies; ihid->probe_retry_state = I2C_HID_PROBE_RETRY_PENDING; i2c_hid_probe_retry_queue(ihid); return 0;" \
	"$(fn 'static int i2c_hid_probe_retry_start(' | sed -n '/probe_retry_start = /,/return/p' | grep -v '^$' | flat)"
eq "0002: on the freezable workqueue, every interval" \
	"queue_delayed_work(system_freezable_wq, &ihid->probe_retry_work, msecs_to_jiffies(I2C_HID_PROBE_RETRY_INTERVAL_MS));" \
	"$(fn 'static void i2c_hid_probe_retry_queue(' | grep -A1 queue_delayed_work | flat)"
eq "0002: the work is set up with the panel follower's" 1 \
	"$(grep -c '^	INIT_DELAYED_WORK(&ihid->probe_retry_work, i2c_hid_probe_retry_work);$' "$C")"
eq "0002: a retry resets, then probes as probe does" \
	"i2c_hid_core_power_up i2c_hid_probe_retry_reset __i2c_hid_core_probe i2c_hid_init_irq i2c_hid_core_register_hid free_irq i2c_hid_core_power_down" \
	"$(fn 'static int i2c_hid_core_probe_retry(' | grep -o -e 'i2c_hid_core_power_up(' -e 'i2c_hid_probe_retry_reset(' -e '__i2c_hid_core_probe(' \
		-e 'i2c_hid_init_irq(' -e 'i2c_hid_core_register_hid(' -e '	free_irq(' -e 'i2c_hid_core_power_down(' | tr -d '(\t' | paste -sd' ' -)"
eq "0002: the reset is a HID RESET to the command register" 2 \
	"$(fn 'static void i2c_hid_probe_retry_reset(' | grep -c -e 'I2C_HID_OPCODE_RESET, 0, 0);' -e '\*(__le16 \*)ihid->cmdbuf = ihid->reset_cmd_reg;')"
eq "0002: only once a descriptor was valid" "if (!ihid->hid->version) return;" \
	"$(fn 'static void i2c_hid_probe_retry_reset(' | grep -A1 'if (!ihid->hid->version)' | flat)"
eq "0002: the command register comes from a validated descriptor" \
	"ihid->quirks = i2c_hid_lookup_quirk(hid->vendor, hid->product); ihid->reset_cmd_reg = ihid->hdesc.wCommandRegister;" \
	"$(fn 'static int __i2c_hid_core_probe(' | grep -A1 'ihid->quirks = ' | flat)"
eq "0002: the work retries until the time is up" \
	"if (ret && i2c_hid_probe_retryable(ihid, ret) && ms + I2C_HID_PROBE_RETRY_INTERVAL_MS <= I2C_HID_PROBE_RETRY_TIMEOUT_MS) { i2c_hid_probe_retry_queue(ihid); return; }" \
	"$(fn 'static void i2c_hid_probe_retry_work(' | sed -n '/^	if (ret && /,/^	}$/p' | flat)"
eq "0002: the log lines" \
	'"probe retry %u succeeded, %u ms after the probe failed\n",|"giving up after %u probe retries in %u ms: %d\n",|"probe failed (%d), retrying every %u s for up to %u s\n", error,' \
	"$(grep -o -e '"probe failed .*' -e '"probe retry %u .*' -e '"giving up after .*' "$C" | paste -sd'|' -)"
eq "0002: success is dev_info, giving up dev_warn" 3 \
	"$(grep -c -e '	dev_info(dev, "probe retry %u succeeded' -e '	dev_warn(dev, "giving up after' -e '^	dev_info(&ihid->client->dev,$' "$C")"
eq "0002: stopping cancels the work and waits for it" \
	"if (READ_ONCE(ihid->probe_retry_state) == I2C_HID_PROBE_RETRY_NONE) return false; cancel_delayed_work_sync(&ihid->probe_retry_work);" \
	"$(fn 'static bool i2c_hid_probe_retry_stop(' | sed -n '/== I2C_HID_PROBE_RETRY_NONE/,/cancel_delayed_work_sync/p' | grep -v '^$' | flat)"
eq "0002: remove stops it first, and frees no IRQ of a device that never came up" \
	"bool down = i2c_hid_probe_retry_stop(ihid); else if (!down) i2c_hid_core_suspend(ihid, true); hid_destroy_device(hid); if (!down) free_irq(client->irq, ihid);" \
	"$(fn 'void i2c_hid_core_remove(' | grep -e 'bool down' -e '!down' -A1 -e 'hid_destroy_device' | grep -v -e '^--$' -e '^$' | grep -v -e 'hid = ihid->hid' | flat)"
eq "0002: shutdown stops it, and sends nothing to a device that never came up" \
	"if (i2c_hid_probe_retry_stop(ihid)) return; i2c_hid_set_power(ihid, I2C_HID_PWR_SLEEP); free_irq(client->irq, ihid);" \
	"$(fn 'void i2c_hid_core_shutdown(' | sed -n '/retry_stop/,/free_irq/p' | grep -v '^$' | flat)"
eq "0002: system sleep stops it" "if (i2c_hid_probe_retry_stop(ihid)) return 0; return i2c_hid_core_suspend(ihid, false);" \
	"$(fn 'static int i2c_hid_core_pm_suspend(' | sed -n '/retry_stop/,/core_suspend/p' | grep -v '^$' | flat)"
eq "0002: resume and restore resume it" 2 \
	"$(fn 'static int i2c_hid_core_pm_res' | grep -c '^	if (i2c_hid_probe_retry_resume(ihid))$')"
eq "0002: resume queues it again only while pending" "case I2C_HID_PROBE_RETRY_PENDING: i2c_hid_probe_retry_queue(ihid); return true;" \
	"$(fn 'static bool i2c_hid_probe_retry_resume(' | grep -A2 'case I2C_HID_PROBE_RETRY_PENDING:' | flat)"
eq "0002: the pm ops are unchanged" 6 "$(sed -n '/^const struct dev_pm_ops i2c_hid_core_pm = {$/,/^};$/p' "$C" | grep -c 'pm_sleep_ptr(i2c_hid_core_pm_')"
eq "0002: the quirk table is unchanged" "$quirks_was" "$(fn '} i2c_hid_quirks\[\] = {')"
eq "0002: the reset handshake is unchanged" "$start_was" "$(fn 'static int i2c_hid_start_hwreset(')"
eq "0002: parse is unchanged" "$parse_was" "$(fn 'static int i2c_hid_parse(')"
eq "0002: register_hid is unchanged" "$register_was" "$(fn 'static int i2c_hid_core_register_hid(')"
eq "0002: core suspend is unchanged" "$suspend_was" "$(fn 'static int i2c_hid_core_suspend(')"
eq "0002: core resume is unchanged" "$resume_was" "$(fn 'static int i2c_hid_core_resume(')"
cp "$C" "$T/core-retry.c"
fails "0002 on a tree that has it fails the build" apply_patch "$K" "$Q"
eq "0002 on a tree that has it is not reverted" "" "$(diff "$T/core-retry.c" "$C")"
unset -f fn flat
unset Q C quirks_was start_was suspend_was resume_was parse_was register_was
