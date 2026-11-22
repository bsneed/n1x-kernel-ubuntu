# SPDX-License-Identifier: GPL-2.0-only
# NVIDIA helpers for scripts/install.sh and scripts/check.sh: which packages belong to which
# driver version, the apt pin, and the nvidia-persistenced unit override. Sourced, not run.
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

# nvidia_before BRANCH DKMS REPLACED: reads installed packages as "name=version" lines and prints
# the lines the first install records for --remove (/var/lib/n1x-kernel-ubuntu/nvidia-before):
# the packages it replaces (the file REPLACED, one name per line, from nvidia_other_versions),
# and BRANCH's packages that are already installed, which --remove must keep (a machine that
# ran Ubuntu's 620 before). DKMS (ours) is never recorded.
nvidia_before() {
	local branch=$1 dkms=$2 replaced=$3 line name b
	while IFS= read -r line; do
		name=${line%%=*}
		[[ -n $name && $name != "$dkms" ]] || continue
		if grep -qxF "$name" "$replaced" || { b=$(nvidia_branch_of "$name") && [[ $b == "$branch" ]]; }; then
			printf '%s\n' "$line"
		fi
	done
}

# nvidia_prebuilt_kernel NAME: the kernel release of a prebuilt-modules package
# (linux-modules-nvidia-615-open-7.0.0-1026-nvidia and its linux-objects-* -> 7.0.0-1026-nvidia);
# fails for others, the metapackage linux-modules-nvidia-615-open-nvidia among them.
nvidia_prebuilt_kernel() {
	[[ $1 =~ ^linux-(modules|objects)-nvidia-[0-9]{3}(-server)?(-open)?-([0-9]+\.[0-9]+\.[0-9]+-.+)$ ]] || return 1
	printf '%s\n' "${BASH_REMATCH[4]}"
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

# Ubuntu's nvidia-compute-utils-620 orders nvidia-persistenced (which runs after sysinit.target)
# Before= systemd-backlight@backlight:nvidia_0 (which runs before it): an ordering cycle that
# systemd breaks at every boot on machines whose panel backlight is the NVIDIA GPU's, as on the
# N1x. A drop-in can't remove an entry from Before= (an empty Before= doesn't reset it), so the
# override is a full copy of the packaged unit without that line. Reported to Ubuntu as
# LP #2175497 (https://bugs.launchpad.net/bugs/2175497); drop this once that is fixed.
# shellcheck disable=SC2034 # used by install.sh and check.sh
PERSISTENCED_UNIT=/usr/lib/systemd/system/nvidia-persistenced.service
PERSISTENCED_OVERRIDE=/etc/systemd/system/nvidia-persistenced.service
PERSISTENCED_CYCLE=Before=systemd-backlight@backlight:nvidia_0.service
PERSISTENCED_MARK='# Generated by n1x-kernel-ubuntu'

# persistenced_override UNIT: prints the override of UNIT (a header, then UNIT without the
# PERSISTENCED_CYCLE line). Fails, printing nothing, if UNIT is missing or has no such line.
persistenced_override() {
	[[ -r $1 ]] && grep -qxF "$PERSISTENCED_CYCLE" "$1" || return 1
	cat <<-EOF
		$PERSISTENCED_MARK (scripts/install.sh) from $1:
		# the packaged unit without "$PERSISTENCED_CYCLE",
		# which orders nvidia-persistenced (after sysinit.target) before systemd-backlight@ (before
		# sysinit.target), an ordering cycle systemd breaks at boot. A drop-in can't drop it.
		# install.sh writes this again on every run and scripts/install.sh --remove deletes it.
		# Remove by hand: sudo rm $PERSISTENCED_OVERRIDE; sudo systemctl daemon-reload
	EOF
	grep -vxF "$PERSISTENCED_CYCLE" "$1"
}

# persistenced_is_ours FILE: true if FILE is an override persistenced_override wrote.
persistenced_is_ours() {
	[[ -f $1 ]] && [[ $(head -1 "$1") == "$PERSISTENCED_MARK "* ]]
}

# persistenced_status UNIT OVERRIDE: check.sh's verdict on the ordering cycle of the packaged
# UNIT and the OVERRIDE in /etc, as one line: "OK message" or "WARN message".
persistenced_status() {
	local unit=$1 over=$2
	if ! grep -qxF "$PERSISTENCED_CYCLE" "$unit"; then
		if persistenced_is_ours "$over"; then
			echo "WARN nvidia-persistenced: our stale override $over still shadows the packaged unit, which no longer has the ordering cycle (sudo bash scripts/install.sh removes it)"
		else
			echo "OK nvidia-persistenced: the packaged unit has no backlight ordering cycle"
		fi
	elif persistenced_is_ours "$over"; then
		if cmp -s <(persistenced_override "$unit") "$over"; then
			echo "OK nvidia-persistenced override without the ordering cycle ($over)"
		else
			echo "WARN nvidia-persistenced override is older than the packaged unit (sudo bash scripts/install.sh)"
		fi
	elif [[ -f $over ]] && ! grep -qxF "$PERSISTENCED_CYCLE" "$over"; then
		echo "OK nvidia-persistenced: your own override, without the ordering cycle ($over)"
	else
		echo "WARN nvidia-persistenced has a boot-time ordering cycle ($PERSISTENCED_CYCLE; sudo bash scripts/install.sh)"
	fi
}
