#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - install the N1x kernel and NVIDIA 620 on Ubuntu 26.04 (ASUS ProArt P16)
#
# Why: Ubuntu's linux-nvidia 7.0 kernel can't run the N1x USB4 host routers, so docks fall
# back to USB 2.0 without displays. This installs the packages scripts/build.sh made:
#  1. linux-image/linux-headers <release> (Omarchy's N1x kernel), next to Ubuntu's kernels;
#  2. NVIDIA $NVIDIA_VERSION: Ubuntu's user space (the same packages as proart-p16-linux's
#     install/02-nvidia.sh, from <codename>-proposed while it is only there) and our DKMS
#     modules with Omarchy's N1x display fixes, built for every kernel with headers. An apt pin
#     keeps the user space at exactly that version, so `apt upgrade` can't split it from the
#     modules (/etc/apt/preferences.d/n1x-kernel-ubuntu-nvidia);
#  3. the USB4 PCI hotplug padding (pci=hpbussize=...) in GRUB_CMDLINE_LINUX_DEFAULT.
# GRUB's default stays the kernel you run now; the new kernel boots once on the next reboot.
# After a good boot, --default makes it the default.
# Remove: sudo bash scripts/install.sh --remove   (back to the NVIDIA packages and GRUB
#         default from before the install, kernel packages purged, cmdline restored)
# Run with: sudo bash scripts/install.sh [--debs DIR] | --default | --remove
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/grub.sh"

DEBS=$REPO/out MODE=install
while [[ $# -gt 0 ]]; do
	case $1 in
	--debs) DEBS=$2; shift 2 ;;
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
GRUB_FILE=/etc/default/grub GRUB_CFG=/boot/grub/grub.cfg
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -q -o Dpkg::Options::=--force-confold)
# NVIDIA user space, as proart-p16-linux's install/02-nvidia.sh installs it for 615.
NV_PKGS=("nvidia-headless-no-dkms-$BRANCH-open" "nvidia-utils-$BRANCH" "libnvidia-gl-$BRANCH"
	"libnvidia-decode-$BRANCH" "libnvidia-encode-$BRANCH" "libnvidia-extra-$BRANCH"
	"libnvidia-fbc1-$BRANCH" "libnvidia-cfg1-$BRANCH" "xserver-xorg-video-nvidia-$BRANCH")
NV_DKMS=nvidia-n1x-dkms-$BRANCH-open

# Installed NVIDIA driver packages as "name=version" (kernel modules included, ours excluded).
nvidia_installed() {
	dpkg-query -W -f '${db:Status-Abbrev}${Package}=${Version}\n' 2>/dev/null |
		sed -n 's/^ii *//p' | grep -E '^(lib)?nvidia-|^xserver-xorg-video-nvidia-|^linux-modules-nvidia-' |
		grep -vE "^($NV_DKMS|nvidia-firmware-|nvidia-vaapi-driver|libnvidia-egl-)" || true
}

# Temporary <codename>-proposed at priority 1 (only versions asked for by name), as
# proart-p16-linux's install/lib.sh does; removed again when the script exits.
proposed_disable() { rm -f "$PROPOSED_SRC" "$PROPOSED_PIN"; }
proposed_enable() {
	local codename uri
	# shellcheck source=/dev/null
	codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
	uri=$(awk '/^URIs:/ {print $2; exit}' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true)
	trap proposed_disable EXIT
	printf 'Types: deb\nURIs: %s\nSuites: %s-proposed\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
		"${uri:-http://archive.ubuntu.com/ubuntu/}" "$codename" >"$PROPOSED_SRC"
	printf 'Package: *\nPin: release a=%s-proposed\nPin-Priority: 1\n' "$codename" >"$PROPOSED_PIN"
	apt-get update -q || warn "not every package source could be refreshed - continuing"
}

grub_point() { # grub_point set-default|reboot KERNELRELEASE
	local id
	id=$(grub_entry_id "$GRUB_CFG" "$2") || die "no GRUB entry for $2 in $GRUB_CFG"
	"grub-$1" "$id"
	msg "grub-$1 $id"
}

dkms_all_kernels() { # build our NVIDIA modules for every kernel that has headers
	local d k
	for d in /lib/modules/*/build; do
		[[ -d $d ]] || continue
		k=${d%/build} k=${k##*/}
		if dkms status -m nvidia-n1x -v "$NVIDIA_VERSION" -k "$k" | grep -q installed; then
			continue
		fi
		msg "Building NVIDIA $NVIDIA_VERSION for $k (DKMS, several minutes)"
		if ! dkms install -m nvidia-n1x -v "$NVIDIA_VERSION" -k "$k"; then
			[[ $k == "$RELEASE" ]] && die "NVIDIA modules failed to build for $k"
			warn "NVIDIA modules failed to build for $k: that kernel will have no GPU driver"
		fi
	done
}

do_install() {
	[[ $(dpkg --print-architecture) == arm64 ]] || die "arm64 only"
	# shellcheck source=/dev/null
	[[ $(. /etc/os-release && echo "$VERSION_ID") == 26.04 ]] || die "Ubuntu 26.04 only"
	grep -qx H7607BA /sys/class/dmi/id/product_name 2>/dev/null ||
		grep -q H7607BA /sys/class/dmi/id/product_name 2>/dev/null ||
		warn "tested on the ASUS ProArt P16 H7607BA only; this is $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
	local img hdr dkmsdeb
	img=$(compgen -G "$DEBS/linux-image-${RELEASE}_*.deb" | head -1) || true
	hdr=$(compgen -G "$DEBS/linux-headers-${RELEASE}_*.deb" | head -1) || true
	dkmsdeb=$(compgen -G "$DEBS/${NV_DKMS}_$NVIDIA_VERSION-*.deb" | head -1) || true
	[[ -f $img && -f $hdr && -f $dkmsdeb ]] || die "missing packages for $RELEASE in $DEBS (run scripts/build.sh)"
	[[ -f $DEBS/SHA256SUMS ]] || die "missing $DEBS/SHA256SUMS"
	(cd "$DEBS" && sha256sum --quiet -c SHA256SUMS) || die "package checksums do not match $DEBS/SHA256SUMS"

	# What --remove goes back to. Kept from the first install, so a reinstall does not overwrite it.
	mkdir -p "$STATE"
	if [[ ! -f $STATE/previous-kernel ]]; then
		local prev
		prev=$(uname -r)
		is_n1x_release "$prev" && die "running $prev but $STATE is missing; boot an Ubuntu kernel first"
		echo "$prev" >"$STATE/previous-kernel"
		nvidia_installed >"$STATE/nvidia-before"
		cp -p "$GRUB_FILE" "$STATE/grub.before"
	fi
	msg "Previous kernel: $(cat "$STATE/previous-kernel"); NVIDIA before: $(paste -sd' ' "$STATE/nvidia-before")"

	cat >"$PIN" <<-EOF
		# n1x-kernel-ubuntu (scripts/install.sh): NVIDIA user space must match the kernel
		# modules of $NV_DKMS exactly. Removed by scripts/install.sh --remove.
		Package: nvidia-dkms-$BRANCH-open
		Pin: version *
		Pin-Priority: -1

		Package: /^(lib)?nvidia-.*-$BRANCH(-open|-server)?$/ /^nvidia-firmware-$BRANCH-/ xserver-xorg-video-nvidia-$BRANCH
		Pin: version $NVIDIA_UBUNTU_VERSION
		Pin-Priority: 1001
	EOF
	proposed_enable

	# Other NVIDIA branches' packages (615 user space, prebuilt 615 modules) go; 620 replaces them.
	local -a remove=() want=()
	local p
	for p in $(nvidia_installed | cut -d= -f1); do
		[[ $p == *-$BRANCH || $p == *-$BRANCH-* ]] || remove+=("$p-")
	done
	for p in "${NV_PKGS[@]}"; do want+=("$p=$NVIDIA_UBUNTU_VERSION"); done
	msg "Installing $RELEASE and NVIDIA $NVIDIA_VERSION"
	"${APT[@]}" install "$img" "$hdr" "$dkmsdeb" "${want[@]}" "${remove[@]}"
	dkms_all_kernels

	msg "Kernel command line: USB4 PCI hotplug padding"
	grub_default_set "$GRUB_FILE" "$(cmdline_add_pci "$(grub_default_get "$GRUB_FILE")")"
	grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"
	update-grub
	# GRUB_DEFAULT=saved: keep the old kernel the default, try the new one once.
	grub_point set-default "$(cat "$STATE/previous-kernel")"
	grub_point reboot "$RELEASE"
	echo
	echo "Done. Reboot: the next boot (only) runs $RELEASE; a hang or reset falls back to"
	echo "$(cat "$STATE/previous-kernel") on the boot after. Check it with bash scripts/check.sh, then"
	echo "make it the default with: sudo bash scripts/install.sh --default"
}

do_default() {
	[[ $(uname -r) == "$RELEASE" ]] || die "boot $RELEASE first (sudo bash scripts/install.sh, reboot)"
	grub_point set-default "$RELEASE"
}

do_remove() {
	[[ -f $STATE/previous-kernel && -f $STATE/nvidia-before ]] ||
		die "$STATE is missing: nothing to restore (was scripts/install.sh run on this machine?)"
	local prev
	prev=$(cat "$STATE/previous-kernel")
	[[ -d /lib/modules/$prev ]] || die "previous kernel $prev is no longer installed"

	rm -f "$PIN"
	proposed_enable
	local -a want=() remove=()
	local p
	mapfile -t want <"$STATE/nvidia-before"
	for p in $(dpkg-query -W -f '${db:Status-Abbrev}${Package}\n' | sed -n 's/^ii *//p' |
		grep -E "^(lib)?nvidia-.*-$BRANCH(-open|-server)?$|^nvidia-firmware-$BRANCH-|^xserver-xorg-video-nvidia-$BRANCH$|^$NV_DKMS$"); do
		grep -q "^$p=" "$STATE/nvidia-before" || remove+=("$p-")
	done
	msg "Restoring NVIDIA: ${want[*]:-(none)}"
	"${APT[@]}" install --allow-downgrades "${want[@]}" "${remove[@]}"

	msg "Kernel command line and GRUB default"
	grub_default_set "$GRUB_FILE" "$(cmdline_remove_pci "$(grub_default_get "$GRUB_FILE")")"
	grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"
	local -a kpkgs
	mapfile -t kpkgs < <(dpkg-query -W -f '${db:Status-Abbrev}${Package}\n' | sed -n 's/^[ir][iHUFWt] *//p' |
		grep -E '^linux-(image|headers)-[0-9]+\.[0-9]+\.[0-9]+-n1x[0-9]+$' || true)
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
