#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - install the N1x kernel and NVIDIA 620 on Ubuntu 26.04 (ASUS ProArt P16)
#
# Why: Ubuntu's linux-nvidia 7.0 kernel can't run the N1x USB4 host routers, so docks fall
# back to USB 2.0 without displays. This installs the packages scripts/build.sh made:
#  1. linux-image/linux-headers <release> (Omarchy's N1x kernel), next to Ubuntu's kernels;
#  2. NVIDIA $NVIDIA_VERSION: Ubuntu's user space (the same packages as proart-p16-linux's
#     install/02-nvidia.sh, from <codename>-proposed while it is only there) and our DKMS
#     modules with Omarchy's N1x display fixes, built for every kernel with headers. It
#     replaces the packages of other NVIDIA driver versions (615) and nothing else. An apt pin
#     keeps the user space at that upstream version, so `apt upgrade` can't split it from the
#     modules (/etc/apt/preferences.d/n1x-kernel-ubuntu-nvidia);
#  3. the USB4 PCI hotplug padding (pci=hpbussize=...) in GRUB_CMDLINE_LINUX_DEFAULT;
#  4. an nvidia-persistenced unit without Ubuntu's boot-time ordering cycle, when needed
#     (/etc/systemd/system/nvidia-persistenced.service).
# Every apt transaction is simulated first; the install stops before changing anything if apt
# can't do it or would remove something else.
# GRUB's default stays the kernel you run now; the new kernel boots once on the next reboot
# (GRUB_DEFAULT=saved, which this sets if needed). After a good boot, --default makes it the
# default, and a later run keeps it.
# Remove: sudo bash scripts/install.sh --remove   (back to the NVIDIA packages, GRUB_DEFAULT,
#         GRUB default and kernel command line from before the install, kernel packages purged)
# Run with: sudo bash scripts/install.sh [--debs DIR] | --default | --remove
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/grub.sh"
. "$(dirname "$0")/lib-nvidia.sh"
. "$(dirname "$0")/lib-install.sh"
. "$(dirname "$0")/lib-steps.sh"

DEBS=$REPO/out MODE=install
while [[ $# -gt 0 ]]; do
	case $1 in
	--debs) need_arg $# "$1"; DEBS=$2; shift 2 ;;
	--default) MODE=default; shift ;;
	--remove) MODE=remove; shift ;;
	*) die "unknown option $1 (see the header of $0)" ;;
	esac
done
require_root
load_sources
RELEASE=$(kernel_release "$KERNEL_VERSION" "$N1X_REVISION")
BRANCH=${NVIDIA_VERSION%%.*}
STATE=/var/lib/n1x-kernel-ubuntu
PIN=/etc/apt/preferences.d/n1x-kernel-ubuntu-nvidia
PROPOSED_SRC=/etc/apt/sources.list.d/n1x-kernel-ubuntu-proposed.sources
PROPOSED_PIN=/etc/apt/preferences.d/n1x-kernel-ubuntu-proposed
GRUB_FILE=/etc/default/grub GRUB_DROPINS=/etc/default/grub.d GRUB_CFG=/boot/grub/grub.cfg
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -q -o Dpkg::Options::=--force-confold)
# NVIDIA user space, as proart-p16-linux's install/02-nvidia.sh installs it for 615.
NV_PKGS=("nvidia-headless-no-dkms-$BRANCH-open" "nvidia-utils-$BRANCH" "libnvidia-gl-$BRANCH"
	"libnvidia-decode-$BRANCH" "libnvidia-encode-$BRANCH" "libnvidia-extra-$BRANCH"
	"libnvidia-fbc1-$BRANCH" "libnvidia-cfg1-$BRANCH" "xserver-xorg-video-nvidia-$BRANCH")
NV_DKMS=nvidia-n1x-dkms-$BRANCH-open
TMP=$(mktemp -d)
trap 'proposed_disable; rm -rf "$TMP"' EXIT

do_install() {
	[[ $(dpkg --print-architecture) == arm64 ]] || die "arm64 only"
	# shellcheck source=/dev/null
	[[ $(. /etc/os-release && echo "$VERSION_ID") == 26.04 ]] || die "Ubuntu 26.04 only"
	n1x_gpu >/dev/null || die "no RTX Spark N1X GPU (10de:2e03, 2e06 or 2e13): this is for N1x laptops only"
	grep -q H7607BA /sys/class/dmi/id/product_name 2>/dev/null ||
		warn "tested on the ASUS ProArt P16 H7607BA only; this is $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
	! secure_boot_enabled || die "Secure Boot is on. This kernel is signed with a throwaway build" \
		"key that the firmware and shim don't trust, so it would not boot. Turn Secure Boot off" \
		"in the firmware setup (or sign the kernel and modules with a key of your own, enrolled" \
		"with mokutil) and run this again."
	grub_preflight
	local img=$DEBS/linux-image-${RELEASE}_${RELEASE}_arm64.deb
	local hdr=$DEBS/linux-headers-${RELEASE}_${RELEASE}_arm64.deb
	local dkmsdeb=$DEBS/${NV_DKMS}_$NVIDIA_VERSION-n1x${NVIDIA_N1X_REVISION}_arm64.deb d
	for d in "$img" "$hdr" "$dkmsdeb"; do [[ -f $d ]] || die "missing $d (run scripts/build.sh)"; done
	[[ -f $DEBS/SHA256SUMS ]] || die "missing $DEBS/SHA256SUMS"
	(cd "$DEBS" && sha256sum --quiet -c SHA256SUMS) || die "package checksums do not match $DEBS/SHA256SUMS"
	# apt takes a .deb whose version is installed for installed, even if it was rebuilt.
	for d in "$img" "$hdr" "$dkmsdeb"; do
		deb_vs_installed "$d" || [[ $? -eq 1 ]] ||
			die "${d##*/} is installed with other files under the same version: raise N1X_REVISION or NVIDIA_N1X_REVISION in sources and rebuild"
	done

	# The kernel GRUB keeps as the default (and falls back to) must get our NVIDIA modules.
	local prev p k
	if [[ -f $STATE/previous-kernel ]]; then
		prev=$(cat "$STATE/previous-kernel")
	else
		prev=$(uname -r)
		is_n1x_release "$prev" && die "running $prev but $STATE is missing; boot an Ubuntu kernel first"
	fi
	[[ -d $MODULES_ROOT/$prev/build ]] ||
		die "$prev, GRUB's default, has no headers, so it would get no NVIDIA driver (sudo apt install linux-headers-$prev)"
	local installed
	installed=$(dpkg_installed)
	local -a remove=()
	mapfile -t remove < <(nvidia_other_versions "$BRANCH" "$NV_DKMS" <<<"$installed")
	for p in "${remove[@]}"; do
		k=$(nvidia_prebuilt_kernel "$p") || continue
		if [[ -f $BOOT_ROOT/vmlinuz-$k && ! -d $MODULES_ROOT/$k/build ]]; then
			die "$p goes, and $k has no headers to build ours (sudo apt install linux-headers-$k)"
		fi
	done

	proposed_enable
	nvidia_pin_text "$BRANCH" "$NVIDIA_VERSION" >"$TMP/pin"
	printf '%s\n' "${remove[@]}" >"$TMP/allowed"
	local -a args=(install "$img" "$hdr" "$dkmsdeb" "${NV_PKGS[@]}" "${remove[@]/%/-}")
	msg "Checking the apt transaction (apt-get -s)"
	apt_simulate "$TMP/allowed" "$BRANCH" "$NVIDIA_VERSION" -o Dir::Etc::Preferences="$TMP/pin" "${args[@]}"

	# What --remove goes back to. Kept from the first install, so a reinstall does not overwrite it.
	mkdir -p "$STATE"
	if [[ ! -f $STATE/previous-kernel ]]; then
		awk -F= 'NR == FNR { r[$0]; next } $1 in r' "$TMP/allowed" - <<<"$installed" >"$STATE/nvidia-before"
		cp -p "$GRUB_FILE" "$STATE/grub.before"
		echo "$prev" >"$STATE/previous-kernel"
	fi
	msg "Previous kernel: $prev; NVIDIA before: $(paste -sd' ' "$STATE/nvidia-before")"

	cp "$TMP/pin" "$PIN"
	msg "Installing $RELEASE and NVIDIA $NVIDIA_VERSION${remove[*]:+, removing ${remove[*]}}"
	"${APT[@]}" "${args[@]}" || die "the apt transaction failed (see above); fix that and run install.sh again"
	dkms_all_kernels
	# The kernel loads the NVIDIA modules from the initramfs; DKMS 3 rebuilds none of them.
	msg "Refreshing every initramfs"
	update-initramfs -u -k all
	persistenced_apply

	msg "Kernel command line: USB4 PCI hotplug padding"
	grub_default_set "$GRUB_FILE" "$(cmdline_add_pci "$(grub_default_get "$GRUB_FILE")")"
	grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"
	# grub-set-default and grub-reboot only work with GRUB_DEFAULT=saved (--remove restores it).
	local was
	was=$(grub_use_saved "$GRUB_FILE")
	[[ -z $was ]] || msg "GRUB_DEFAULT=saved (was: $was), so the fallback boot below works"
	update-grub
	grub_verify
	echo
	if [[ $(grub_saved_entry) == "$(grub_entry_id "$GRUB_CFG" "$RELEASE")" ]]; then
		# Made the default with --default before; a re-run keeps that choice.
		msg "GRUB's default stays $RELEASE (chosen with --default)"
		echo "Done. $RELEASE stays GRUB's default. Reboot if the kernel or NVIDIA modules changed."
		return
	fi
	# Keep the old kernel the default, try the new one once.
	grub_point set-default "$prev"
	grub_point reboot "$RELEASE"
	echo
	echo "Done. Reboot: the next boot (only) runs $RELEASE; a hang or reset falls back to"
	echo "$prev on the boot after. Check it with bash scripts/check.sh, then"
	echo "make it the default with: sudo bash scripts/install.sh --default"
}

do_default() {
	[[ $(uname -r) == "$RELEASE" ]] || die "boot $RELEASE first (sudo bash scripts/install.sh, reboot)"
	[[ $(grub_var_get "$GRUB_FILE" GRUB_DEFAULT) == saved ]] ||
		die "GRUB_DEFAULT in $GRUB_FILE is not saved, so GRUB would ignore this (run sudo bash scripts/install.sh)"
	grub_point set-default "$RELEASE"
}

do_remove() {
	[[ -f $STATE/previous-kernel && -f $STATE/nvidia-before ]] ||
		die "$STATE is missing: nothing to restore (was scripts/install.sh run on this machine?)"
	local prev
	prev=$(cat "$STATE/previous-kernel")
	[[ -d $MODULES_ROOT/$prev ]] || die "previous kernel $prev is no longer installed"

	# What comes back is the packages from before, at their current versions: the exact ones
	# may have left the archive (a security respin of 615).
	local -a want=() remove=() kpkgs=()
	mapfile -t want < <(cut -d= -f1 "$STATE/nvidia-before" | grep . || true)
	mapfile -t remove < <(dpkg_installed | nvidia_restore_removals "$BRANCH" "$NV_DKMS" "$STATE/nvidia-before")
	mapfile -t kpkgs < <(dpkg-query -W -f '${db:Status-Abbrev}${Package}\n' | n1x_kernel_pkgs)
	proposed_enable
	# The pin stays until the restore has worked, so a failure can't leave 620 unpinned.
	if printf '%s\n' "${want[@]}" | grep -qx "nvidia-dkms-$BRANCH-open"; then
		nvidia_pin_text "$BRANCH" "$NVIDIA_VERSION" user-space-only >"$PIN"
	fi
	printf '%s\n' "${remove[@]}" >"$TMP/allowed"
	printf '%s\n' "${kpkgs[@]}" >"$TMP/kallowed"
	msg "Checking the apt transactions (apt-get -s)"
	apt_simulate "$TMP/allowed" "" "" install "${want[@]}" "${remove[@]/%/-}"
	[[ ${#kpkgs[@]} -eq 0 ]] || apt_simulate "$TMP/kallowed" "" "" purge "${kpkgs[@]}"

	msg "Restoring NVIDIA: ${want[*]:-(none)}${remove[*]:+; removing ${remove[*]}}"
	"${APT[@]}" install "${want[@]}" "${remove[@]/%/-}" ||
		die "restoring the NVIDIA packages failed (see above); the apt pin stays, so 620 stays whole. Fix that and run --remove again"
	rm -f "$PIN"
	update-initramfs -u -k all
	persistenced_drop

	msg "Kernel command line and GRUB default"
	local cmdline
	cmdline=$(grub_default_get "$GRUB_FILE") || die "cannot edit GRUB_CMDLINE_LINUX_DEFAULT in $GRUB_FILE"
	if [[ -f $STATE/grub.before ]]; then
		# The user's own pci= values come back; see cmdline_remove_pci.
		grub_default_set "$GRUB_FILE" "$(cmdline_remove_pci "$cmdline" "$(grub_default_get "$STATE/grub.before")")"
		grub_restore_default "$GRUB_FILE" "$STATE/grub.before"
	else
		grub_default_set "$GRUB_FILE" "$(cmdline_remove_pci "$cmdline")"
	fi
	grep -E '^(GRUB_DEFAULT|GRUB_CMDLINE_LINUX_DEFAULT)=' "$GRUB_FILE"
	if [[ ${#kpkgs[@]} -gt 0 ]]; then
		is_n1x_release "$(uname -r)" && warn "removing the running kernel $(uname -r): reboot afterwards"
		msg "Purging ${kpkgs[*]}"
		"${APT[@]}" purge "${kpkgs[@]}"
	fi
	update-grub
	grub-editenv - unset next_entry
	grub_point set-default "$prev"
	rm -rf "$STATE"
	echo
	echo "Removed. GRUB boots $prev by default again; reboot if you ran the N1x kernel."
}

"do_$MODE"
