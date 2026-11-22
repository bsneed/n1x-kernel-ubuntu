# SPDX-License-Identifier: GPL-2.0-only
# NVIDIA helpers for scripts/install.sh and scripts/check.sh: which packages belong to which
# driver version, and the apt pin. Sourced, not run.
# The functions have no side effects; tests/run.sh covers them.
# shellcheck shell=bash

# nvidia_branch_of NAME: the driver version (branch, three digits: 615, 620) whose package NAME
# is, e.g. nvidia-utils-615, libnvidia-gl-615, nvidia-driver-615-open, nvidia-firmware-615-*,
# linux-modules-nvidia-615-open-<kernel>. Fails for packages of no particular driver version
# (nvidia-settings, nvidia-prime, nvidia-container-toolkit, libnvidia-container1, ...).
nvidia_branch_of() {
	local re
	for re in '^nvidia-firmware-([0-9]{3})-' '^linux-(modules|objects)-nvidia-([0-9]{3})-' \
		'^xserver-xorg-video-nvidia-([0-9]{3})$' '^(lib)?nvidia-.*-([0-9]{3})(-server)?(-open)?$'; do
		if [[ $1 =~ $re ]]; then
			printf '%s\n' "${BASH_REMATCH[2]:-${BASH_REMATCH[1]}}"
			return 0
		fi
	done
	return 1
}

# nvidia_other_versions BRANCH DKMS: reads installed packages as "name=version" lines and prints
# the names install.sh replaces: every package of another driver version (615's user space,
# its prebuilt linux-modules-nvidia-615-open-*), and Ubuntu's DKMS package of BRANCH, which DKMS
# (ours) stands in for. Packages of no driver version stay.
nvidia_other_versions() {
	local branch=$1 dkms=$2 line name b
	while IFS= read -r line; do
		name=${line%%=*}
		[[ -n $name && $name != "$dkms" ]] || continue
		if [[ $name == "nvidia-dkms-$branch-open" || $name == "nvidia-dkms-$branch" ]]; then
			printf '%s\n' "$name"
		elif b=$(nvidia_branch_of "$name") && [[ $b != "$branch" ]]; then
			printf '%s\n' "$name"
		fi
	done
}

# nvidia_prebuilt_kernel NAME: the kernel release of a prebuilt-modules package
# (linux-modules-nvidia-615-open-7.0.0-1026-nvidia -> 7.0.0-1026-nvidia); fails for others.
nvidia_prebuilt_kernel() {
	[[ $1 =~ ^linux-modules-nvidia-[0-9]{3}(-server)?(-open)?-(.+)$ ]] || return 1
	printf '%s\n' "${BASH_REMATCH[3]}"
}

# nvidia_restore_removals BRANCH DKMS BEFORE: reads installed packages as "name=version" lines
# and prints the names --remove takes away: BRANCH's packages and DKMS (ours), except those
# listed in BEFORE ("name=version" lines of what the install replaced or found).
nvidia_restore_removals() {
	local branch=$1 dkms=$2 before=$3 line name b
	while IFS= read -r line; do
		name=${line%%=*}
		[[ -n $name ]] || continue
		if [[ $name == "$dkms" ]] || { b=$(nvidia_branch_of "$name") && [[ $b == "$branch" ]]; }; then
			grep -q "^$name=" "$before" || printf '%s\n' "$name"
		fi
	done
}

# nvidia_pin_text BRANCH VERSION [user-space-only]: /etc/apt/preferences.d/n1x-kernel-ubuntu-nvidia.
# NVIDIA's user space must be the upstream VERSION of our DKMS modules; any Ubuntu revision of
# it will do (a respin, or the move from -proposed to -updates, keeps the modules matched).
# Ubuntu's own DKMS package of BRANCH can't come back, since ours stands in for it; with a
# third argument that stanza is left out (--remove putting Ubuntu's DKMS package back).
nvidia_pin_text() {
	cat <<-EOF
		# n1x-kernel-ubuntu (scripts/install.sh): NVIDIA's user space must be $2, the version
		# of the kernel modules in nvidia-n1x-dkms-$1-open (any Ubuntu revision of $2).
		# Newer NVIDIA versions wait until n1x-kernel-ubuntu moves to them.
		# Removed by scripts/install.sh --remove.
	EOF
	[[ -n ${3:-} ]] || printf 'Package: nvidia-dkms-%s-open\nPin: version *\nPin-Priority: -1\n\n' "$1"
	cat <<-EOF
		Package: /^(lib)?nvidia-.*-$1(-open|-server)?$/ /^nvidia-firmware-$1-/ xserver-xorg-video-nvidia-$1
		Pin: version $2-*
		Pin-Priority: 1001
	EOF
}
