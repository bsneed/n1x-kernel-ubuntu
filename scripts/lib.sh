# SPDX-License-Identifier: GPL-2.0-only
# Shared helpers for scripts/*.sh. Sourced, not run.
# shellcheck shell=bash

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

msg() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

# need_arg $# OPTION: for option parsing, fail unless OPTION has a value after it.
need_arg() {
	[[ $1 -ge 2 ]] || die "$2 needs a value"
}

require_root() {
	[[ $EUID -eq 0 ]] || die "run as root (sudo bash $0)"
}

# Load the pinned inputs (KEY=value lines) from $1, default $REPO/sources.
load_sources() {
	local file=${1:-$REPO/sources}
	[[ -r $file ]] || die "missing $file"
	# shellcheck source=/dev/null
	. "$file"
	local key
	for key in KERNEL_VERSION KERNEL_URL KERNEL_SHA256 OMARCHY_REPO OMARCHY_COMMIT \
		OMARCHY_RECIPE BASE_CONFIG_URL BASE_CONFIG_SHA256 BASE_CONFIG_PATH \
		BASE_CONFIG_FILE_SHA256 N1X_REVISION NVIDIA_VERSION NVIDIA_URL NVIDIA_SHA256 \
		NVIDIA_UBUNTU_VERSION NVIDIA_N1X_REVISION; do
		[[ -n ${!key:-} ]] || die "$file does not set $key"
	done
}

# The kernel's own version for a kernel.org release: 7.3 -> 7.3.0, 7.3.5 -> 7.3.5.
kernel_base_version() {
	local v=$1
	if [[ $v =~ ^[0-9]+\.[0-9]+$ ]]; then
		printf '%s.0\n' "$v"
	elif [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		printf '%s\n' "$v"
	else
		die "unsupported kernel version '$v' (want X.Y or X.Y.Z)"
	fi
}

# uname -r of our kernel: kernel_release 7.3 1 -> 7.3.0-n1x1.
kernel_release() {
	local base
	base=$(kernel_base_version "$1") || return 1
	[[ $2 =~ ^[1-9][0-9]*$ ]] || die "unsupported N1X revision '$2' (want a positive integer)"
	printf '%s-n1x%s\n' "$base" "$2"
}

# True if $1 is one of our kernel releases (X.Y.Z-n1xN).
is_n1x_release() {
	[[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+-n1x[1-9][0-9]*$ ]]
}

sha256_of() {
	if command -v sha256sum >/dev/null; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

# verify_sha256 FILE EXPECTED: fail unless FILE has that SHA-256.
verify_sha256() {
	local actual
	actual=$(sha256_of "$1")
	[[ $actual == "$2" ]] || die "checksum mismatch for $1: expected $2, got $actual"
}

# fetch URL SHA256 DEST: download once into DEST and verify it every time.
fetch() {
	local url=$1 sum=$2 dest=$3
	if [[ ! -f $dest ]]; then
		msg "Downloading $url"
		curl -fsSL --retry 3 --proto '=https' -o "$dest.part" "$url"
		mv "$dest.part" "$dest"
	fi
	verify_sha256 "$dest" "$sum"
}

# apply_patch TREE PATCH: apply PATCH (-p1) to TREE exactly as written: no fuzz, never a
# question, and a patch that is already applied fails. GNU patch's --batch alone assumes such
# a patch is reversed and reverts it with exit status 0, which would silently undo a fix that
# upstream has merged.
apply_patch() {
	patch -d "$1" -p1 --forward --batch --fuzz=0 --quiet <"$2"
}
