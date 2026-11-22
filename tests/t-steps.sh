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
# shellcheck disable=SC2329 # called as "grub-$1" by grub_point
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
unset -f mkcfg id_of update-grub grub-editenv grub-set-default steps
