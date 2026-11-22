# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib-install.sh with stand-ins for dkms, dpkg-query and mokutil, and fake roots.
# Sourced by tests/run.sh, which defines eq, fails, skip, $T, $P and $OSI.
# shellcheck shell=bash
. scripts/lib-nvidia.sh
. scripts/lib-install.sh
NVIDIA_VERSION=620.73.04

# --- DKMS builds for every kernel (a failure for a bootable kernel is fatal) -------------------
MODULES_ROOT=$T/modules BOOT_ROOT=$T/boot
mkdir -p "$BOOT_ROOT"
for k in 7.3.0-n1x1 7.0.0-1026-nvidia 7.0.0-44-generic 7.0.0-30-generic; do
	mkdir -p "$MODULES_ROOT/$k/build"
done
touch "$BOOT_ROOT/vmlinuz-7.3.0-n1x1" "$BOOT_ROOT/vmlinuz-7.0.0-1026-nvidia" "$BOOT_ROOT/vmlinuz-7.0.0-44-generic"
: >"$T/dkms-installed"
: >"$T/dkms-broken"
# dkms status|install -m nvidia-n1x -v VERSION -k KERNEL
dkms() {
	case $1 in
	status) if grep -qx "$7" "$T/dkms-installed"; then echo "nvidia-n1x/$5, $7, aarch64: installed"; fi ;;
	install)
		echo "$7" >>"$T/dkms-built"
		if grep -qx "$7" "$T/dkms-broken"; then return 10; fi
		echo "$7" >>"$T/dkms-installed"
		;;
	esac
}
eq "bootable kernels" "7.0.0-1026-nvidia 7.0.0-44-generic 7.3.0-n1x1" "$(kernels_bootable | sort | paste -sd' ')"
: >"$T/dkms-built"
eq "builds for every kernel with headers" 0 "$( (dkms_all_kernels) >/dev/null 2>&1; echo $?)"
eq "built every kernel with headers" "7.0.0-1026-nvidia 7.0.0-30-generic 7.0.0-44-generic 7.3.0-n1x1" \
	"$(sort "$T/dkms-built" | paste -sd' ')"
printf '7.0.0-1026-nvidia\n7.0.0-44-generic\n7.0.0-30-generic\n7.3.0-n1x1\n' >"$T/dkms-installed"
: >"$T/dkms-built"
dkms_all_kernels >/dev/null 2>&1
eq "skips kernels that have the modules" "" "$(cat "$T/dkms-built")"
# The stock fallback kernel (the GRUB default after install) failing to build must stop the install.
printf '7.3.0-n1x1\n' >"$T/dkms-installed"
printf '7.0.0-1026-nvidia\n' >"$T/dkms-broken"
eq "a failed build for the fallback kernel is fatal" 1 "$( (dkms_all_kernels) >/dev/null 2>&1; echo $?)"
eq "the error names the kernel" 1 "$(dkms_all_kernels 2>&1 | grep -c '^ERROR: NVIDIA 620.73.04 modules failed to build for 7.0.0-1026-nvidia,')"
eq "it still builds the other kernels" "7.0.0-1026-nvidia 7.0.0-30-generic 7.0.0-44-generic" \
	"$( (dkms_all_kernels) >/dev/null 2>&1; sort -u "$T/dkms-built" | paste -sd' ')"
printf '7.3.0-n1x1\n7.0.0-1026-nvidia\n7.0.0-44-generic\n' >"$T/dkms-installed"
printf '7.3.0-n1x1\n' >"$T/dkms-broken"
: >"$T/dkms-installed"
eq "a failed build for the new kernel is fatal" 1 "$( (dkms_all_kernels) >/dev/null 2>&1; echo $?)"
printf '7.3.0-n1x1\n7.0.0-1026-nvidia\n7.0.0-44-generic\n' >"$T/dkms-installed"
printf '7.0.0-30-generic\n' >"$T/dkms-broken"
eq "a failed build for headers without a kernel only warns" "0 1" \
	"$( (dkms_all_kernels) 2>"$T/err" >/dev/null; echo "$? $(grep -c 'no kernel image' "$T/err")")"
mkdir -p "$MODULES_ROOT/7.0.0-20-nvidia"
touch "$BOOT_ROOT/vmlinuz-7.0.0-20-nvidia"
eq "a bootable kernel without headers is reported" "0 1" \
	"$( (dkms_all_kernels) 2>"$T/err" >/dev/null; echo "$? $(grep -c 'no NVIDIA modules for 7.0.0-20-nvidia: no headers' "$T/err")")"
unset -f dkms

# --- our kernel packages ----------------------------------------------------------------------
eq "n1x kernel packages" "linux-image-7.3.0-n1x1 linux-headers-7.3.0-n1x1 linux-image-7.3.0-n1x2" \
	"$(printf '%s\n' 'ii linux-image-7.3.0-n1x1' 'ii linux-headers-7.3.0-n1x1' 'iU linux-image-7.3.0-n1x2' \
		'rc linux-image-7.3.0-n1x0' 'ii linux-image-7.0.0-1026-nvidia' 'ii linux-libc-dev' \
		'ii linux-image-7.3.0-n1x1-dbg' 'ii linux-headers-7.3-n1x1' | n1x_kernel_pkgs | paste -sd' ')"
eq "n1x kernel packages of none" "" "$(printf 'ii bash\n' | n1x_kernel_pkgs)"

# --- apt-get -s output -------------------------------------------------------------------------
cat >"$T/sim" <<'SIM'
NOTE: This is only a simulation!
Remv nvidia-driver-615-open [615.71.09-0ubuntu0.26.04.2]
Remv nvidia-utils-615 [615.71.09-0ubuntu0.26.04.2]
Inst nvidia-utils-620 (620.73.04-0ubuntu0.26.04.1 Ubuntu:26.04/resolute-proposed [arm64])
Inst nvidia-kernel-common-620 [620.73.04-0ubuntu0.26.04.1] (620.73.04-0ubuntu0.26.04.2 Ubuntu:26.04/resolute-updates [arm64])
Inst nvidia-n1x-dkms-620-open (620.73.04-n1x2 local-deb [arm64])
Inst libpciaccess0 (0.18.1-1ubuntu4.1 Ubuntu:26.04/resolute-updates [arm64])
Conf nvidia-utils-620 (620.73.04-0ubuntu0.26.04.1 Ubuntu:26.04/resolute-proposed [arm64])
SIM
printf 'nvidia-driver-615-open\nnvidia-utils-615\n' >"$T/allowed"
eq "sim: what was asked for" 0 "$(apt_sim_check "$T/allowed" 620 620.73.04 <"$T/sim"; echo $?)"
printf 'Remv nvidia-settings [580.95.05-1]\nRemv nvidia-container-toolkit:arm64 [1.17.8-1]\n' >>"$T/sim"
eq "sim: unexpected removals" "apt would also remove nvidia-settings|apt would also remove nvidia-container-toolkit|1" \
	"$(apt_sim_check "$T/allowed" 620 620.73.04 <"$T/sim" | paste -sd'|')|$(apt_sim_check "$T/allowed" 620 620.73.04 <"$T/sim" >/dev/null; echo $?)"
printf 'Inst nvidia-utils-620 (620.80.01-0ubuntu0.26.04.1 Ubuntu:26.04/resolute-updates [arm64])\n' >"$T/sim2"
eq "sim: another upstream version" "apt would install nvidia-utils-620 620.80.01-0ubuntu0.26.04.1, not 620.73.04" \
	"$(apt_sim_check "$T/allowed" 620 620.73.04 <"$T/sim2")"
printf 'Inst nvidia-utils-615 (615.71.09-0ubuntu0.26.04.3 Ubuntu:26.04/resolute-updates [arm64])\nPurg nvidia-utils-620 [620.73.04-0ubuntu0.26.04.1]\n' >"$T/sim3"
printf 'nvidia-utils-620\n' >"$T/allowed3"
eq "sim: restore checks removals only" 0 "$(apt_sim_check "$T/allowed3" <"$T/sim3"; echo $?)"
eq "sim: nothing to do" 0 "$(apt_sim_check "$T/allowed3" 620 620.73.04 </dev/null; echo $?)"

# --- a rebuilt .deb with the same version ------------------------------------------------------
if command -v dpkg-deb >/dev/null; then
	mkdeb() { # mkdeb DIR CONTENT [md5sums]
		mkdir -p "$T/$1/DEBIAN" "$T/$1/usr/share/n1x"
		printf 'Package: n1x-test\nVersion: 1.0-n1x1\nArchitecture: all\nMaintainer: t <t@t>\nDescription: t\n' >"$T/$1/DEBIAN/control"
		printf '%s\n' "$2" >"$T/$1/usr/share/n1x/file"
		ln -sf file "$T/$1/usr/share/n1x/link"
		[[ -z ${3:-} ]] || (cd "$T/$1" && md5sum usr/share/n1x/file >DEBIAN/md5sums)
		dpkg-deb --root-owner-group --build "$T/$1" "$T/$1.deb" >/dev/null
	}
	mkdeb deb-a one md5sums
	mkdeb deb-b two
	mkdeb deb-c one
	eq "md5sums from the package" "$(cd "$T/deb-a" && md5sum usr/share/n1x/file)" "$(deb_md5sums "$T/deb-a.deb")"
	eq "md5sums computed without them" "$(deb_md5sums "$T/deb-a.deb")" "$(deb_md5sums "$T/deb-c.deb")"
	DPKG_INFO=$T/info
	mkdir -p "$DPKG_INFO"
	(cd "$T/deb-a" && md5sum usr/share/n1x/file) >"$DPKG_INFO/n1x-test.md5sums"
	dpkg_status="ii 1.0-n1x1"
	dpkg-query() { printf '%s' "$dpkg_status"; }
	eq "deb installed with the same files" 0 "$(deb_vs_installed "$T/deb-a.deb"; echo $?)"
	eq "deb without md5sums, same files" 0 "$(deb_vs_installed "$T/deb-c.deb"; echo $?)"
	eq "deb rebuilt with other files, same version" 2 "$(deb_vs_installed "$T/deb-b.deb"; echo $?)"
	dpkg_status="ii 1.0-n1x0"
	eq "deb of another version" 1 "$(deb_vs_installed "$T/deb-b.deb"; echo $?)"
	dpkg_status=""
	eq "deb not installed" 1 "$(deb_vs_installed "$T/deb-b.deb"; echo $?)"
	dpkg_status="ii 1.0-n1x1"
	rm "$DPKG_INFO/n1x-test.md5sums"
	eq "deb installed without a record of its files" 2 "$(deb_vs_installed "$T/deb-a.deb"; echo $?)"
	unset -f dpkg-query mkdeb
	DPKG_INFO=/var/lib/dpkg/info
else
	skip "deb_vs_installed" "no dpkg-deb"
fi

# --- the fallback kernel -----------------------------------------------------------------------
for k in 7.0.0-1026-nvidia 7.0.0-1026-nvidia-64k 7.1.0-3-nvidia; do
	eq "$k is Ubuntu's linux-nvidia" 0 "$(ubuntu_nvidia_kernel "$k"; echo $?)"
done
for k in 7.0.0-44-generic 7.3.0-n1x1 7.0.0-1026-nvidia-foo nvidia 7.0.0-nvidia; do
	eq "$k is not Ubuntu's linux-nvidia" 1 "$(ubuntu_nvidia_kernel "$k"; echo $?)"
done

# --- the fallback kernel after apt autoremove ------------------------------------------------------
MODULES_ROOT=$T/fb-modules BOOT_ROOT=$T/fb-boot
mkdir -p "$BOOT_ROOT"
mkk() { mkdir -p "$MODULES_ROOT/$1" && touch "$BOOT_ROOT/vmlinuz-$1"; }
for k in 7.3.0-n1x1 7.0.0-44-generic 7.0.0-999-nvidia 7.0.0-1030-nvidia 7.0.0-1028-nvidia \
	7.0.0-1030-nvidia-64k 7.0.0-1028-nvidia-64k; do
	mkk "$k"
done
mkdir -p "$MODULES_ROOT/7.0.0-1026-nvidia/updates" # left behind by DKMS, no kernel image
mkdir -p "$MODULES_ROOT/7.0.0-1040-nvidia"           # an image half removed: no vmlinuz
eq "fallback: the recorded kernel while it is installed" 7.0.0-1028-nvidia "$(fallback_kernel 7.0.0-1028-nvidia)"
eq "fallback: an installed non-nvidia kernel stays" 7.0.0-44-generic "$(fallback_kernel 7.0.0-44-generic)"
eq "fallback: the newest linux-nvidia (version order) once it is gone" 7.0.0-1030-nvidia "$(fallback_kernel 7.0.0-1026-nvidia)"
eq "fallback: the -64k flavour for a -64k kernel" 7.0.0-1030-nvidia-64k "$(fallback_kernel 7.0.0-1026-nvidia-64k)"
eq "fallback: linux-nvidia for a removed generic kernel" 7.0.0-1030-nvidia "$(fallback_kernel 7.0.0-40-generic)"
eq "fallback: never our kernel" 0 "$(fallback_kernel 7.0.0-1026-nvidia | grep -c n1x)"
mkk 7.1.0-3-nvidia
eq "fallback: a newer kernel version wins" 7.1.0-3-nvidia "$(fallback_kernel 7.0.0-1026-nvidia)"
rm -r "$MODULES_ROOT"/7.*-nvidia* "$BOOT_ROOT"/vmlinuz-7.*-nvidia*
mkk 7.0.0-1030-nvidia-64k
eq "fallback: the other flavour when that is all there is" 7.0.0-1030-nvidia-64k "$(fallback_kernel 7.0.0-1026-nvidia)"
rm -r "$MODULES_ROOT/7.0.0-1030-nvidia-64k"
fails "fallback: no linux-nvidia kernel left" fallback_kernel 7.0.0-1026-nvidia
eq "fallback: prints nothing then" "" "$(fallback_kernel 7.0.0-1026-nvidia 2>&1)"
mkk 7.0.0-1030-nvidia
cat >"$T/fb-before" <<'PKGS'
linux-modules-nvidia-615-open-7.0.0-1026-nvidia=7.0.0-1026.27
linux-objects-nvidia-615-open-7.0.0-1026-nvidia=7.0.0-1026.27
linux-modules-nvidia-615-open-nvidia=7.0.0-1026.27
linux-modules-nvidia-615-open-7.0.0-1030-nvidia=7.0.0-1030.31
nvidia-utils-615=615.71.09-0ubuntu0.26.04.2

PKGS
eq "restore wants: not the modules of a removed kernel; the metapackage brings the new ones" \
	"linux-modules-nvidia-615-open-nvidia linux-modules-nvidia-615-open-7.0.0-1030-nvidia nvidia-utils-615" \
	"$(nvidia_restore_wants "$T/fb-before" 2>/dev/null | paste -sd' ')"
eq "restore wants: says what it leaves out" \
	"WARNING: not reinstalling linux-modules-nvidia-615-open-7.0.0-1026-nvidia: kernel 7.0.0-1026-nvidia is no longer installed|WARNING: not reinstalling linux-objects-nvidia-615-open-7.0.0-1026-nvidia: kernel 7.0.0-1026-nvidia is no longer installed" \
	"$(nvidia_restore_wants "$T/fb-before" 2>&1 >/dev/null | paste -sd'|')"
mkk 7.0.0-1026-nvidia
eq "restore wants: everything while the kernel is installed" \
	"$(cut -d= -f1 "$T/fb-before" | grep . | paste -sd' ')" "$(nvidia_restore_wants "$T/fb-before" 2>&1 | paste -sd' ')"
eq "restore wants: nothing recorded" "" "$(nvidia_restore_wants /dev/null)"
unset -f mkk

# --- the N1x GPU ------------------------------------------------------------------------------
mkpci() { mkdir -p "$T/pci-$1/$2" && printf '%s\n' "$3" >"$T/pci-$1/$2/vendor" && printf '%s\n' "$4" >"$T/pci-$1/$2/device"; }
mkpci p16 0000:00:00.0 0x10de 0x22ce
mkpci p16 000f:01:00.0 0x10de 0x2e06
mkpci spark 000f:01:00.0 0x10de 0x2e12
mkpci other 0000:01:00.0 0x8086 0x2e06
mkpci upper 0000:01:00.0 0x10DE 0x2E13
eq "N1x GPU of a ProArt P16" 10de:2e06 "$(PCI_ROOT=$T/pci-p16 n1x_gpu)"
eq "N1x GPU in upper case" 10de:2e13 "$(PCI_ROOT=$T/pci-upper n1x_gpu)"
fails "no N1x GPU on a DGX Spark (GB10)" env PCI_ROOT="$T/pci-spark" bash -c '. scripts/lib-install.sh; n1x_gpu'
fails "no N1x GPU from another vendor" env PCI_ROOT="$T/pci-other" bash -c '. scripts/lib-install.sh; n1x_gpu'
fails "no N1x GPU without PCI devices" env PCI_ROOT="$T/pci-none" bash -c '. scripts/lib-install.sh; n1x_gpu'
unset -f mkpci

# --- Secure Boot -------------------------------------------------------------------------------
mokutil() { printf '%s\n' "$sb_out"; }
sb_out="SecureBoot enabled"
eq "secure boot enabled" 0 "$(secure_boot_enabled; echo $?)"
sb_out="SecureBoot disabled"
eq "secure boot disabled" 1 "$(secure_boot_enabled; echo $?)"
sb_out=$'SecureBoot disabled\nPlatform is in Setup Mode'
eq "secure boot in setup mode" 1 "$(secure_boot_enabled; echo $?)"
# mokutil fails off EFI or without efivarfs; then the SecureBoot variable decides.
mokutil() { return 1; }
printf '\006\000\000\000\001' >"$T/sb1"
printf '\006\000\000\000\000' >"$T/sb0"
eq "secure boot from the EFI variable, enabled" 0 "$(SB_EFIVAR=$T/sb1 secure_boot_enabled; echo $?)"
eq "secure boot from the EFI variable, disabled" 1 "$(SB_EFIVAR=$T/sb0 secure_boot_enabled; echo $?)"
eq "secure boot without mokutil or the variable" 1 "$(SB_EFIVAR=$T/none secure_boot_enabled; echo $?)"
unset -f mokutil
MODULES_ROOT=/lib/modules BOOT_ROOT=/boot
