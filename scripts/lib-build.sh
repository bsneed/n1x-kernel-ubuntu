# SPDX-License-Identifier: GPL-2.0-only
# Helpers for scripts/build.sh and scripts/nvidia-dkms.sh: Omarchy's recipe, the checkout's
# commit, and the DKMS package templates. Sourced, not run; tests/run.sh covers them.
# shellcheck shell=bash

# pkgbuild_info RECIPEDIR: reads the recipe's PKGBUILD (in a subshell, as makepkg would for
# aarch64) and prints what build.sh takes from it, one "key value..." line each:
#   pkgver 7.3 | rcpatch <_rcpatch or empty> | tarball <file> <sha256> | patch <file> (in order)
# The patches are every *.patch source except the nvidia-* ones, which belong to its NVIDIA
# modules, as its prepare() applies them (a "name::url" source is the file "name", .zst dropped).
pkgbuild_info() {
	(cd "$1" && CARCH=aarch64 bash -c '
		set -e
		source ./PKGBUILD >/dev/null
		printf "pkgver %s\nrcpatch %s\n" "$pkgver" "${_rcpatch:-}"
		for i in "${!source[@]}"; do
			src=${source[i]%%::*} src=${src##*/}
			[[ $src == "${_srcname:-linux-$pkgver}".tar.* && $src != *.sign ]] && printf "tarball %s %s\n" "$src" "${sha256sums[i]:-}"
		done
		for src in "${source[@]}"; do
			src=${src%%::*} src=${src##*/} src=${src%.zst}
			[[ $src == *.patch && $src != nvidia-* ]] && printf "patch %s\n" "$src"
		done
		true')
}

# source_commit: the commit of this checkout, with "-dirty" if it has changes or untracked
# files. Fails outside a git checkout.
source_commit() {
	local head
	head=$(git -C "$REPO" rev-parse HEAD 2>/dev/null) || { echo "$REPO is not a git checkout" >&2; return 1; }
	if [[ -n $(git -C "$REPO" status --porcelain 2>/dev/null) ]]; then
		printf '%s-dirty\n' "$head"
	else
		printf '%s\n' "$head"
	fi
}

# dkms_subst FILE: FILE (nvidia-dkms/*) with @NVIDIA_VERSION@, @NVIDIA_BRANCH@, @DEB_VERSION@
# and @INSTALLED_SIZE@ filled in from NVIDIA_VERSION, BRANCH, DEB_VERSION and SIZE.
dkms_subst() {
	sed -e "s/@NVIDIA_VERSION@/$NVIDIA_VERSION/g" -e "s/@NVIDIA_BRANCH@/$BRANCH/g" \
		-e "s/@DEB_VERSION@/$DEB_VERSION/g" -e "s/@INSTALLED_SIZE@/${SIZE:-0}/g" "$1"
}
