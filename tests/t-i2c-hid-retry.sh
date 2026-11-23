# SPDX-License-Identifier: GPL-2.0-only
# Tests of patches/ubuntu/0002's probe retry by running it: tests/i2c-hid-retry/harness.c, built
# with the host's C compiler against the patched i2c-hid-core.c (the fixture with 0002 applied),
# so it tests whatever the patch says now. Skipped only when there is no C compiler.
# Sourced by tests/run.sh, which defines eq, fails, skip and $T.
# shellcheck shell=bash

IHR=$T/i2c-hid-retry
IHC=$IHR/drivers/hid/i2c-hid/i2c-hid-core.c
mkdir -p "${IHC%/*}"
cp tests/fixtures/linux-7.3/drivers/hid/i2c-hid/i2c-hid-core.c "$IHC"
eq "retry harness: 0002 applies to the fixture" 0 \
	"$(apply_patch "$IHR" patches/ubuntu/0002-hid-i2c-hid-retry-a-failed-probe-on-the-asus-proart-p16.patch >/dev/null 2>&1; echo $?)"

# extract LIST: the blocks of the patched file whose first line starts with a line of LIST (a
# #define is one line; anything else runs to the first line starting with "}"), in the file's
# order. Fails, naming it, if a line of LIST doesn't start exactly one block.
extract() {
	awk 'NR == FNR { want[++n] = $0; next }
		!open { for (i = 1; i <= n; i++) if (index($0, want[i]) == 1) { seen[i]++; open = $0 !~ /^#define/; print; next } }
		open { print; if (/^}/) { open = 0; print "" } }
		END { for (i = 1; i <= n; i++) if (seen[i] != 1 && want[i] !~ /^#define I2C_HID_$/) { print "extract: " seen[i] + 0 " of " want[i] > "/dev/stderr"; bad = 1 }
			exit bad }' "$1" "$IHC"
}
cat >"$IHR/types.list" <<'EOF'
#define I2C_HID_
#define i2c_hid_dbg(
enum i2c_hid_probe_retry_state {
struct i2c_hid_desc {
struct i2c_hid {
static const struct dmi_system_id i2c_hid_probe_retry_dmi[] = {
EOF
cat >"$IHR/funcs.list" <<'EOF'
static bool i2c_hid_probe_retryable(
static const char *i2c_hid_probe_retry_check_rdesc(
static int i2c_hid_probe_address(
static size_t i2c_hid_encode_command(
static int i2c_hid_init_irq(
static int i2c_hid_parse(
static int i2c_hid_fetch_hid_descriptor(
static int i2c_hid_core_power_up(
static void i2c_hid_core_power_down(
static void i2c_hid_core_shutdown_tail(
static void i2c_hid_core_restore_sequence(
static int __i2c_hid_core_probe(
static int i2c_hid_core_register_hid(
static void i2c_hid_probe_retry_reset(
static int i2c_hid_core_probe_retry(
static void i2c_hid_probe_retry_queue(
static void i2c_hid_probe_retry_work(
static bool i2c_hid_probe_retry_stop(
static bool i2c_hid_probe_retry_resume(
static int i2c_hid_probe_retry_start(
int i2c_hid_core_probe(
void i2c_hid_core_remove(
void i2c_hid_core_shutdown(
static int i2c_hid_core_pm_suspend(
static int i2c_hid_core_pm_resume(
static int i2c_hid_core_pm_restore(
EOF
eq "retry harness: the patched types extract" 0 "$(extract "$IHR/types.list" >"$IHR/core-types.h" 2>"$IHR/extract.err"; echo $?)"
eq "retry harness: the patched functions extract" 0 "$(extract "$IHR/funcs.list" >"$IHR/core-funcs.h" 2>>"$IHR/extract.err"; echo $?)"
eq "retry harness: nothing missing or doubled" "" "$(cat "$IHR/extract.err")"

ihr_cc=
for c in "${CC:-}" cc gcc clang; do
	[[ -n $c ]] && command -v "$c" >/dev/null && { ihr_cc=$c; break; }
done
if [[ -z $ihr_cc ]]; then
	skip "retry harness" "no C compiler (cc, gcc or clang)"
else
	# -Wno-pointer-sign, as the kernel builds (scripts/Makefile.warn): i2c_hid_parse() passes a char * as u8 *
	eq "retry harness: builds with $ihr_cc" "" "$("$ihr_cc" -std=gnu11 -Wall -Wno-unused-function -Wno-pointer-sign \
		-Werror=implicit-function-declaration -Werror=incompatible-pointer-types -Werror=int-conversion \
		-I tests/i2c-hid-retry -I "$IHR" -o "$IHR/harness" tests/i2c-hid-retry/harness.c 2>&1)"
	if [[ -x $IHR/harness ]]; then
		eq "retry harness: runs to the end" 0 "$("$IHR/harness" >"$IHR/out" 2>&1; echo $?)"
		ihr_n=0
		while IFS=$'\t' read -r tag name want got; do
			case $tag in
			CHECK) eq "retry: $name" "$want" "$got"; ihr_n=$((ihr_n + 1)) ;;
			DONE) eq "retry harness: every check reported" "$name" "$ihr_n" ;;
			*) eq "retry harness: only checks on stdout" "" "$tag $name $want $got" ;;
			esac
		done <"$IHR/out"
		eq "retry harness: finished" 1 "$(grep -c '^DONE	' "$IHR/out")"
		unset ihr_n
	fi
fi
unset IHR IHC ihr_cc
unset -f extract
