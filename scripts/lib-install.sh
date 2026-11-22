# SPDX-License-Identifier: GPL-2.0-only
# Helpers for scripts/install.sh that read the system through dpkg, apt, dkms and mokutil.
# Sourced, not run. tests/run.sh covers them with stand-ins for those tools and fake roots.
# shellcheck shell=bash

DPKG_INFO=${DPKG_INFO:-/var/lib/dpkg/info}
MODULES_ROOT=${MODULES_ROOT:-/lib/modules}
BOOT_ROOT=${BOOT_ROOT:-/boot}
PCI_ROOT=${PCI_ROOT:-/sys/bus/pci/devices}

# dpkg_installed: the installed packages as "name=version" lines.
dpkg_installed() {
	dpkg-query -W -f '${db:Status-Abbrev}${Package}=${Version}\n' 2>/dev/null | sed -n 's/^ii *//p'
}

# n1x_kernel_pkgs: reads "${db:Status-Abbrev}${Package}" lines (dpkg-query) and prints our
# kernel packages that are installed or half-installed (linux-image/headers-X.Y.Z-n1xN).
n1x_kernel_pkgs() {
	sed -n 's/^[ir][iHUFWt] *//p' | grep -E '^linux-(image|headers)-[0-9]+\.[0-9]+\.[0-9]+-n1x[0-9]+$' || true
}

# apt_sim_check ALLOWED [BRANCH VERSION]: reads `apt-get -s` output and prints a line for each
# thing in it that the caller did not ask for: a package removed that is not in the file
# ALLOWED (one name per line), or a package of driver BRANCH installed at another upstream
# version than VERSION. Fails if it printed anything.
apt_sim_check() {
	local allowed=$1 branch=${2:-} version=${3:-} verb name rest v bad=0
	while read -r verb name rest; do
		name=${name%%:*}
		case $verb in
		Remv | Purg)
			grep -qxF "$name" "$allowed" || { echo "apt would also remove $name"; bad=1; } ;;
		Inst)
			[[ -n $branch && $(nvidia_branch_of "$name") == "$branch" ]] || continue
			v=${rest#*(} v=${v%% *}
			[[ $v == "$version"-* ]] || { echo "apt would install $name $v, not $version"; bad=1; } ;;
		esac
	done
	return "$bad"
}

# deb_md5sums DEB: the "md5  path" lines of DEB's files, as dpkg records them on install (from
# DEB's md5sums, or computed from its files if it has none), sorted.
deb_md5sums() {
	local tmp
	if dpkg-deb --ctrl-tarfile "$1" | tar -t 2>/dev/null | grep -qx './md5sums'; then
		dpkg-deb --ctrl-tarfile "$1" | tar -xO ./md5sums | sort
		return
	fi
	tmp=$(mktemp -d)
	dpkg-deb -x "$1" "$tmp"
	(cd "$tmp" && find . -type f -printf '%P\0' | LC_ALL=C sort -z | xargs -0r md5sum) | sort
	rm -rf "$tmp"
}

# deb_vs_installed DEB: 0 if DEB's package is installed at DEB's version with the same files,
# 1 if it is not installed at that version, 2 if it is but its files differ (a rebuild without
# a new revision, which apt would take for installed and skip).
deb_vs_installed() {
	local pkg ver md5
	pkg=$(dpkg-deb -f "$1" Package) && ver=$(dpkg-deb -f "$1" Version) || return 1
	[[ $(dpkg-query -W -f '${db:Status-Abbrev}${Version}' "$pkg" 2>/dev/null) == "ii $ver" ]] || return 1
	for md5 in "$DPKG_INFO/$pkg.md5sums" "$DPKG_INFO/$pkg:arm64.md5sums" ""; do [[ -f $md5 ]] && break; done
	[[ -n $md5 ]] && cmp -s <(deb_md5sums "$1") <(sort "$md5") && return 0
	return 2
}

# n1x_gpu: prints the N1x laptop GPU (RTX Spark N1X, 10de:2e03, 2e06 or 2e13) as vendor:device,
# or fails if there is none (a DGX Spark's GB10 is 10de:2e12).
n1x_gpu() {
	local d id
	for d in "$PCI_ROOT"/*; do
		[[ -r $d/vendor && -r $d/device ]] || continue
		id="$(<"$d/vendor"):$(<"$d/device")"
		case ${id,,} in
		0x10de:0x2e03 | 0x10de:0x2e06 | 0x10de:0x2e13)
			id=${id,,}
			printf '%s\n' "${id//0x/}"
			return 0
			;;
		esac
	done
	return 1
}

# secure_boot_enabled: true if UEFI Secure Boot is on (mokutil --sb-state, or the SecureBoot
# EFI variable without mokutil). Our kernel is signed with a throwaway key, so shim would
# refuse to boot it.
secure_boot_enabled() {
	local out var=${SB_EFIVAR:-/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-e8b5d0e0d2af}
	if command -v mokutil >/dev/null && out=$(mokutil --sb-state 2>/dev/null); then
		[[ $out == *"SecureBoot enabled"* ]]
		return
	fi
	[[ -r $var && $(od -An -tu1 -j4 -N1 "$var" | tr -d ' ') == 1 ]]
}

# ubuntu_nvidia_kernel RELEASE: true for Ubuntu's linux-nvidia kernels (7.0.0-1026-nvidia and
# its -64k sibling), the Ubuntu kernels with the N1x platform drivers.
ubuntu_nvidia_kernel() {
	[[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-nvidia(-64k)?$ ]]
}

# kernel_installed RELEASE: true if RELEASE has a /boot/vmlinuz-<release> and modules.
kernel_installed() { [[ -f $BOOT_ROOT/vmlinuz-$1 && -d $MODULES_ROOT/$1 ]]; }

# kernels_bootable: every kernel release with a /boot/vmlinuz-<release> and modules.
kernels_bootable() {
	local d k
	for d in "$MODULES_ROOT"/*/; do
		k=${d%/} k=${k##*/}
		[[ -f $BOOT_ROOT/vmlinuz-$k ]] && printf '%s\n' "$k"
	done
	return 0
}

# fallback_kernel PREV: the kernel GRUB falls back to and --remove goes back to. PREV (recorded at
# the first install) while it is installed; once it is gone (apt autoremove keeps only the running
# and the two newest kernels), the newest installed Ubuntu linux-nvidia kernel, of PREV's flavour
# (-64k or not) if there is one. Fails if there is none.
fallback_kernel() {
	local prev=$1 k want64=no is64
	local -a same=() other=()
	if kernel_installed "$prev"; then
		printf '%s\n' "$prev"
		return 0
	fi
	[[ $prev == *-64k ]] && want64=yes
	for k in $(kernels_bootable); do
		ubuntu_nvidia_kernel "$k" || continue
		is64=no
		[[ $k == *-64k ]] && is64=yes
		if [[ $is64 == "$want64" ]]; then same+=("$k"); else other+=("$k"); fi
	done
	if [[ ${#same[@]} -gt 0 ]]; then
		printf '%s\n' "${same[@]}" | sort -V | tail -1
	elif [[ ${#other[@]} -gt 0 ]]; then
		printf '%s\n' "${other[@]}" | sort -V | tail -1
	else
		return 1
	fi
}

# nvidia_restore_wants BEFORE: the names in BEFORE ("name=version" lines, nvidia-before) that
# --remove reinstalls: all but the prebuilt modules of a kernel that is no longer installed
# (linux-modules-nvidia-615-open-7.0.0-1026-nvidia once apt has removed 1026), which apt could
# not install without that kernel. The metapackage (linux-modules-nvidia-615-open-nvidia)
# brings the modules of the current one.
nvidia_restore_wants() {
	local name k
	while IFS= read -r name; do
		name=${name%%=*}
		[[ -n $name ]] || continue
		if k=$(nvidia_prebuilt_kernel "$name") && ! kernel_installed "$k"; then
			warn "not reinstalling $name: kernel $k is no longer installed"
			continue
		fi
		printf '%s\n' "$name"
	done <"$1"
}

# dkms_all_kernels: builds our NVIDIA modules (nvidia-n1x NVIDIA_VERSION) for every kernel that
# has headers. Ubuntu's DKMS hook builds only for the running and the newest kernel. A failed
# build for a kernel that boots is fatal: the N1x has no other display engine, so that kernel
# (the fallback among them) would come up without a GPU driver.
dkms_all_kernels() {
	local d k
	local -a failed=() nohdr=()
	for k in $(kernels_bootable); do
		[[ -d $MODULES_ROOT/$k/build ]] || nohdr+=("$k")
	done
	for d in "$MODULES_ROOT"/*/build; do
		[[ -d $d ]] || continue
		k=${d%/build} k=${k##*/}
		dkms status -m nvidia-n1x -v "$NVIDIA_VERSION" -k "$k" 2>/dev/null | grep -q installed && continue
		msg "Building NVIDIA $NVIDIA_VERSION for $k (DKMS, several minutes)"
		dkms install -m nvidia-n1x -v "$NVIDIA_VERSION" -k "$k" && continue
		if [[ -f $BOOT_ROOT/vmlinuz-$k ]]; then
			failed+=("$k")
		else
			warn "NVIDIA modules failed to build for $k, which has headers but no kernel image"
		fi
	done
	[[ ${#nohdr[@]} -eq 0 ]] ||
		warn "no NVIDIA modules for ${nohdr[*]}: no headers (sudo apt install linux-headers-<release>)"
	[[ ${#failed[@]} -eq 0 ]] ||
		die "NVIDIA $NVIDIA_VERSION modules failed to build for ${failed[*]}, which would boot without a GPU driver. See /var/lib/dkms/nvidia-n1x/$NVIDIA_VERSION/build/make.log. GRUB's default is still the kernel you ran before the install; sudo bash scripts/install.sh --remove goes back."
}
