# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib-steps.sh's GRUB steps, with stand-ins for update-grub and grub-editenv,
# grub-set-default and grub-reboot that log their calls, and a fake /etc/default/grub and grub.cfg.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash
. scripts/lib-steps.sh
RELEASE=7.3.0-n1x1
GRUB_FILE=$T/steps-grub GRUB_CFG=$T/steps-grub.cfg
SU=0e2a9a8c-5b8e-4a8e-9a43-3b0f7f1e2d11
mkcfg() { # mkcfg KERNELRELEASE...: grub.cfg with those kernels in Ubuntu's submenu
	local k
	printf "submenu 'Advanced options for Ubuntu' \$menuentry_id_option 'gnulinux-advanced-%s' {\n" "$SU"
	for k in "$@"; do
		printf "\tmenuentry 'Ubuntu, with Linux %s' \$menuentry_id_option 'gnulinux-%s-advanced-%s' {\n\t}\n" "$k" "$k" "$SU"
	done
	printf '}\n'
}
id_of() { printf 'gnulinux-advanced-%s>gnulinux-%s-advanced-%s' "$SU" "$1" "$SU"; }
: >"$T/steps-env"
update-grub() { echo update-grub >>"$T/steps-log"; [[ ! -f $T/steps-update-grub-fails ]]; }
grub-editenv() { # grub-editenv - list | unset VAR
	case $2 in
	list) cat "$T/steps-env" ;;
	unset) echo "grub-editenv unset $3" >>"$T/steps-log" ;;
	esac
}
# shellcheck disable=SC2317,SC2329 # called as "grub-$1" by grub_point (SC2317 before shellcheck 0.10)
grub-set-default() { echo "grub-set-default $1" >>"$T/steps-log"; printf 'saved_entry=%s\n' "$1" >"$T/steps-env"; }
steps() { : >"$T/steps-log"; ("$@") >/dev/null 2>"$T/steps-err"; echo "$?|$(paste -sd'|' "$T/steps-log")"; }

# --- the default is the old kernel before any package changes (G3) --------------------------------
# First install on stock Ubuntu: GRUB_DEFAULT=0, nothing saved, no entry for the new kernel yet.
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\n' >"$GRUB_FILE"
mkcfg 7.0.0-1026-nvidia >"$GRUB_CFG"
eq "grub_default_is without an entry" 1 "$(grub_default_is "$RELEASE"; echo $?)"
eq "keep fallback: saved, update-grub, then the old kernel the default" \
	"0|update-grub|grub-set-default $(id_of 7.0.0-1026-nvidia)" "$(steps grub_keep_fallback 7.0.0-1026-nvidia)"
eq "keep fallback: sets GRUB_DEFAULT=saved" "GRUB_DEFAULT=saved|GRUB_TIMEOUT=5" "$(paste -sd'|' "$GRUB_FILE")"
eq "keep fallback: the old kernel is saved_entry" "$(id_of 7.0.0-1026-nvidia)" "$(grub_saved_entry)"
eq "keep fallback: says what GRUB_DEFAULT was" "==> GRUB_DEFAULT=saved (was: GRUB_DEFAULT=0), so GRUB keeps its default and the fallback boot works" \
	"$(printf 'GRUB_DEFAULT=0\n' >"$GRUB_FILE"; grub_keep_fallback 7.0.0-1026-nvidia 2>/dev/null | head -1)"
# A re-run after --default: the new kernel stays the default.
mkcfg 7.3.0-n1x1 7.0.0-1026-nvidia >"$GRUB_CFG"
printf 'saved_entry=%s\n' "$(id_of 7.3.0-n1x1)" >"$T/steps-env"
eq "grub_default_is the new kernel" 0 "$(grub_default_is "$RELEASE"; echo $?)"
eq "grub_default_is not the old kernel" 1 "$(grub_default_is 7.0.0-1026-nvidia; echo $?)"
eq "keep fallback: keeps a default chosen with --default" "0|update-grub" "$(steps grub_keep_fallback 7.0.0-1026-nvidia)"
eq "keep fallback: GRUB_DEFAULT=saved stays as it is" "GRUB_DEFAULT=saved" "$(cat "$GRUB_FILE")"
# A re-run before --default: saved_entry is the old kernel, and stays.
printf 'saved_entry=%s\n' "$(id_of 7.0.0-1026-nvidia)" >"$T/steps-env"
eq "keep fallback: a re-run points at the old kernel again" \
	"0|update-grub|grub-set-default $(id_of 7.0.0-1026-nvidia)" "$(steps grub_keep_fallback 7.0.0-1026-nvidia)"
# Failures stop before the packages change, and say why.
eq "keep fallback: an old kernel without an entry stops" "1|update-grub" "$(steps grub_keep_fallback 7.0.0-1020-nvidia)"
eq "keep fallback: names the missing entry" "ERROR: no GRUB entry for 7.0.0-1020-nvidia in $GRUB_CFG" "$(cat "$T/steps-err")"
touch "$T/steps-update-grub-fails"
eq "keep fallback: a failed update-grub stops before grub-set-default" "1|update-grub" "$(steps grub_keep_fallback 7.0.0-1026-nvidia)"
eq "keep fallback: says update-grub failed" 1 "$(grep -c '^ERROR: update-grub failed' "$T/steps-err")"
rm "$T/steps-update-grub-fails"
# shellcheck disable=SC2016 # a literal $(...) in the file
printf 'GRUB_DEFAULT=$(echo 0)\n' >"$GRUB_FILE"
eq "keep fallback: a GRUB_DEFAULT it can't edit stops first" "1|" "$(steps grub_keep_fallback 7.0.0-1026-nvidia)"

# --- --remove points GRUB back at the old kernel (G4) ---------------------------------------------
mkcfg 7.3.0-n1x1 7.0.0-1026-nvidia >"$GRUB_CFG"
printf 'saved_entry=%s\n' "$(id_of 7.3.0-n1x1)" >"$T/steps-env"
eq "back to: drops a pending one-time boot, then the old kernel the default" \
	"0|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)" "$(steps grub_back_to 7.0.0-1026-nvidia)"
eq "back to: the old kernel is saved_entry" "$(id_of 7.0.0-1026-nvidia)" "$(grub_saved_entry)"
eq "back to: twice is the same" "0|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)" \
	"$(steps grub_back_to 7.0.0-1026-nvidia)"
eq "back to: a kernel without an entry stops" "1|grub-editenv unset next_entry" "$(steps grub_back_to 7.0.0-1020-nvidia)"

# --- the order of the package steps against GRUB (G3, G4) -----------------------------------------
# apt-get logs what it was asked, and GRUB_DEFAULT, the saved_entry kernel and the pin it ran with.
APT=(apt-get -y) PIN=$T/steps-etc-pin
# shellcheck disable=SC2317,SC2329 # called as "${APT[@]}" (SC2317 before shellcheck 0.10)
apt-get() {
	echo "apt-get $* [$(grep '^GRUB_DEFAULT=' "$GRUB_FILE") $(grub_saved_entry | sed -n 's/^.*>gnulinux-\(.*\)-advanced-.*$/\1/p') pin:$(cat "$PIN" 2>/dev/null)]" >>"$T/steps-log"
	[[ ! -f $T/steps-apt-fails ]]
}
echo new >"$T/steps-new-pin"
# First install on stock Ubuntu.
printf 'GRUB_DEFAULT=0\n' >"$GRUB_FILE"
mkcfg 7.0.0-1026-nvidia >"$GRUB_CFG"
: >"$T/steps-env"
rm -f "$PIN"
eq "install: GRUB keeps the old kernel before apt runs, with the pin" \
	"0|update-grub|grub-set-default $(id_of 7.0.0-1026-nvidia)|apt-get -y install k.deb nvidia-utils-620 [GRUB_DEFAULT=saved 7.0.0-1026-nvidia pin:new]" \
	"$(steps install_packages 7.0.0-1026-nvidia "$T/steps-new-pin" install k.deb nvidia-utils-620)"
eq "install: the pin is in /etc" new "$(cat "$PIN")"
printf 'GRUB_DEFAULT=0\n' >"$GRUB_FILE"
rm -f "$PIN"
eq "install: no GRUB entry for the old kernel stops before the pin and apt" "1|update-grub" \
	"$(steps install_packages 7.0.0-1020-nvidia "$T/steps-new-pin" install k.deb)"
eq "install: no pin written then" no "$([[ -e $PIN ]] && echo yes || echo no)"
touch "$T/steps-apt-fails"
eq "install: a failed apt transaction stops" \
	"1|update-grub|grub-set-default $(id_of 7.0.0-1026-nvidia)|apt-get -y install k.deb [GRUB_DEFAULT=saved 7.0.0-1026-nvidia pin:new]" \
	"$(steps install_packages 7.0.0-1026-nvidia "$T/steps-new-pin" install k.deb)"
eq "install: says the transaction failed" 1 "$(grep -c '^ERROR: the apt transaction failed' "$T/steps-err")"
rm "$T/steps-apt-fails"

# --remove after --default: 7.3 is the default and a one-time boot may be pending.
mkcfg 7.3.0-n1x1 7.0.0-1026-nvidia >"$GRUB_CFG"
printf 'saved_entry=%s\n' "$(id_of 7.3.0-n1x1)" >"$T/steps-env"
echo old >"$PIN"
eq "restore: GRUB boots the old kernel before apt takes our modules away" \
	"0|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)|apt-get -y install nvidia-utils-615 nvidia-n1x-dkms-620-open- [GRUB_DEFAULT=saved 7.0.0-1026-nvidia pin:new]" \
	"$(steps restore_packages 7.0.0-1026-nvidia "$T/steps-new-pin" install nvidia-utils-615 nvidia-n1x-dkms-620-open-)"
eq "restore: the pin goes once the restore has worked" no "$([[ -e $PIN ]] && echo yes || echo no)"
echo old >"$PIN"
eq "restore: without a rewritten pin, apt runs with the one in /etc" \
	"0|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)|apt-get -y install nvidia-utils-615 [GRUB_DEFAULT=saved 7.0.0-1026-nvidia pin:old]" \
	"$(steps restore_packages 7.0.0-1026-nvidia "$T/steps-none" install nvidia-utils-615)"
echo old >"$PIN"
touch "$T/steps-apt-fails"
eq "restore: a failed restore stops" \
	"1|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)|apt-get -y install nvidia-utils-615 [GRUB_DEFAULT=saved 7.0.0-1026-nvidia pin:new]" \
	"$(steps restore_packages 7.0.0-1026-nvidia "$T/steps-new-pin" install nvidia-utils-615)"
eq "restore: the pin stays after a failed restore" new "$(cat "$PIN")"
rm "$T/steps-apt-fails"
echo old >"$PIN"
eq "restore: no GRUB entry for the old kernel stops before the pin and apt" "1|grub-editenv unset next_entry" \
	"$(steps restore_packages 7.0.0-1020-nvidia "$T/steps-new-pin" install nvidia-utils-615)"
eq "restore: the pin in /etc is unchanged then (H4)" old "$(cat "$PIN")"

# --- the end of --remove: GRUB_DEFAULT goes back only after the purge (H2) -------------------------
# Stock GRUB_DEFAULT=0 before the install; saved_entry already points at the old kernel.
rm -f "$PIN"
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\n' >"$T/steps-grub.before"
kp=(linux-image-7.3.0-n1x1 linux-headers-7.3.0-n1x1)
printf 'GRUB_DEFAULT=saved\nGRUB_TIMEOUT=5\n' >"$GRUB_FILE"
eq "remove kernels: purge with GRUB_DEFAULT=saved, then update-grub with it back, then the old kernel" \
	"0|apt-get -y purge ${kp[*]} [GRUB_DEFAULT=saved 7.0.0-1026-nvidia pin:]|update-grub|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)" \
	"$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-grub.before" "${kp[@]}")"
eq "remove kernels: GRUB_DEFAULT is what it was" "GRUB_DEFAULT=0|GRUB_TIMEOUT=5" "$(paste -sd'|' "$GRUB_FILE")"
printf 'GRUB_DEFAULT=saved\nGRUB_TIMEOUT=5\n' >"$GRUB_FILE"
touch "$T/steps-apt-fails"
eq "remove kernels: a failed purge stops before update-grub" \
	"1|apt-get -y purge ${kp[*]} [GRUB_DEFAULT=saved 7.0.0-1026-nvidia pin:]" \
	"$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-grub.before" "${kp[@]}")"
eq "remove kernels: a failed purge leaves GRUB_DEFAULT=saved, so no update-grub can boot 7.3" \
	"GRUB_DEFAULT=saved|GRUB_TIMEOUT=5" "$(paste -sd'|' "$GRUB_FILE")"
eq "remove kernels: says the purge failed and what boots" 1 \
	"$(grep -c "^ERROR: purging ${kp[*]} failed (see above); GRUB boots 7.0.0-1026-nvidia by default" "$T/steps-err")"
rm "$T/steps-apt-fails"
eq "remove kernels: nothing to purge" \
	"0|update-grub|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)" \
	"$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-grub.before")"
eq "remove kernels: nothing to purge, GRUB_DEFAULT back too" "GRUB_DEFAULT=0" "$(grep '^GRUB_DEFAULT=' "$GRUB_FILE")"
printf 'GRUB_DEFAULT=saved\n' >"$GRUB_FILE"
eq "remove kernels: no copy from before, GRUB_DEFAULT stays" \
	"0|update-grub|grub-editenv unset next_entry|grub-set-default $(id_of 7.0.0-1026-nvidia)|GRUB_DEFAULT=saved" \
	"$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-none")|$(cat "$GRUB_FILE")"
printf 'GRUB_TIMEOUT=5\n' >"$T/steps-grub.before"
printf 'GRUB_DEFAULT=saved\nGRUB_TIMEOUT=5\n' >"$GRUB_FILE"
eq "remove kernels: GRUB_DEFAULT unset before, unset again, and it goes on" "0|GRUB_TIMEOUT=5" \
	"$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-grub.before" | cut -d'|' -f1)|$(paste -sd'|' "$GRUB_FILE")"
printf 'export GRUB_DEFAULT=0\n' >"$T/steps-grub.before"
printf 'GRUB_DEFAULT=saved\n' >"$GRUB_FILE"
eq "remove kernels: a copy it can't read stops before update-grub, with GRUB_DEFAULT=saved" "1||GRUB_DEFAULT=saved" \
	"$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-grub.before")|$(cat "$GRUB_FILE")"
eq "remove kernels: says GRUB_DEFAULT can't go back" 1 \
	"$(grep -c "^ERROR: cannot put GRUB_DEFAULT back from $T/steps-grub.before (see above); GRUB boots 7.0.0-1026-nvidia by default" "$T/steps-err")"
printf 'GRUB_DEFAULT=saved\n' >"$GRUB_FILE"
touch "$T/steps-update-grub-fails"
eq "remove kernels: a failed update-grub stops" "1|update-grub" "$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-none")"
eq "remove kernels: says update-grub failed and what boots" 1 \
	"$(grep -c '^ERROR: update-grub failed (see above); GRUB boots 7.0.0-1026-nvidia by default' "$T/steps-err")"
rm "$T/steps-update-grub-fails"
# shellcheck disable=SC2317,SC2329 # called by remove_kernels (SC2317 before shellcheck 0.10)
uname() { echo 7.3.0-n1x1; }
eq "remove kernels: warns when it purges the running kernel" 1 \
	"$(steps remove_kernels 7.0.0-1026-nvidia "$T/steps-none" "${kp[@]}" >/dev/null; grep -c '^WARNING: removing the running kernel 7.3.0-n1x1' "$T/steps-err")"
unset -f uname
unset kp
unset -f mkcfg id_of update-grub grub-editenv grub-set-default steps apt-get
