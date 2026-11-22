#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - build the kernel and NVIDIA DKMS .debs (Ubuntu 26.04, arm64)
#
# Why: Omarchy's linux-omarchy-aarch64 recipe makes USB4/Thunderbolt and the rest of the NVIDIA
# N1x platform work; Ubuntu's linux-nvidia 7.0 kernel has none of the USB4 patches. This script
# builds that recipe for Ubuntu: kernel.org $KERNEL_VERSION + Omarchy's patches in the recipe's
# order + patches/ubuntu, on Ubuntu's linux-nvidia config + config/n1x.config, packaged with the
# kernel's own `make bindeb-pkg`. It also builds the NVIDIA open modules' DKMS package
# (scripts/nvidia-dkms.sh) and test-builds those modules against the new kernel.
# Every input is pinned in ./sources and checked against its SHA-256 (git commit for Omarchy).
# The checkout must be clean (its commit goes into out/SOURCE and the DKMS package and sets
# the build timestamps); --allow-dirty builds anyway and marks the commit -dirty.
# Output: out/*.deb, out/SHA256SUMS and out/SOURCE. Work tree: build/ (safe to delete).
# Remove: rm -rf build out
# Run with: bash scripts/build.sh [--jobs N] [--prepare-only] [--skip-nvidia-test] [--allow-dirty]
#           (on Ubuntu 26.04 arm64 with the packages in scripts/build-deps.txt installed,
#            or anywhere with Docker: bash scripts/container-build.sh)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-build.sh"

JOBS=$(nproc)
PREPARE_ONLY=0
NVIDIA_TEST=1
ALLOW_DIRTY=0
while [[ $# -gt 0 ]]; do
	case $1 in
	--jobs) need_arg $# "$1"; JOBS=$2; shift 2 ;;
	--prepare-only) PREPARE_ONLY=1; shift ;;
	--skip-nvidia-test) NVIDIA_TEST=0; shift ;;
	--allow-dirty) ALLOW_DIRTY=1; shift ;;
	*) die "unknown option $1" ;;
	esac
done

[[ $(uname -m) == aarch64 ]] || die "build on arm64 (this is $(uname -m))"
load_sources
RELEASE=$(kernel_release "$KERNEL_VERSION" "$N1X_REVISION")
BUILD=$REPO/build
DL=$BUILD/dl
OUT=$REPO/out
SRC=$BUILD/linux-$KERNEL_VERSION
mkdir -p "$DL" "$OUT"

# Reproducible metadata from the commit: packages built from it are the same packages.
COMMIT=$(source_commit) || die "build from a git checkout of n1x-kernel-ubuntu"
if [[ $COMMIT == *-dirty ]]; then
	[[ $ALLOW_DIRTY -eq 1 ]] || die "the checkout has changes or untracked files (git status); commit them, or build with --allow-dirty"
	warn "building from a checkout with changes: the packages carry ${COMMIT%-dirty}'s version and time but not its content"
fi
SOURCE_DATE_EPOCH=$(git -C "$REPO" log -1 --format=%ct) || die "git log failed in $REPO"
export SOURCE_DATE_EPOCH
export KBUILD_BUILD_TIMESTAMP="@$SOURCE_DATE_EPOCH"
export KBUILD_BUILD_USER=n1x-kernel-ubuntu KBUILD_BUILD_HOST=n1x-kernel-ubuntu
export DEBFULLNAME='Brandon Sneed' DEBEMAIL=brandon@redf.net

# Ubuntu 26.04's default coreutils are uutils (Rust), whose `install -D` fails when parallel
# calls create the same directory ("cannot create directory"), which make -j dtbs_install
# does. Use GNU install (gnu-coreutils' gnuinstall) when it is there.
if install --version 2>/dev/null | grep -q uutils && command -v gnuinstall >/dev/null; then
	mkdir -p "$BUILD/bin"
	ln -sf "$(command -v gnuinstall)" "$BUILD/bin/install"
	export PATH=$BUILD/bin:$PATH
fi

msg "Building $RELEASE with $JOBS jobs"

# --- Sources -------------------------------------------------------------------------------
fetch "$KERNEL_URL" "$KERNEL_SHA256" "$DL/${KERNEL_URL##*/}"
fetch "$BASE_CONFIG_URL" "$BASE_CONFIG_SHA256" "$DL/${BASE_CONFIG_URL##*/}"
fetch "$NVIDIA_URL" "$NVIDIA_SHA256" "$DL/${NVIDIA_URL##*/}"

OMARCHY=$DL/omarchy-pkgs
if [[ $(git -C "$OMARCHY" rev-parse HEAD 2>/dev/null) != "$OMARCHY_COMMIT" ]]; then
	msg "Fetching omarchy-pkgs $OMARCHY_COMMIT"
	rm -rf "$OMARCHY"
	git init -q "$OMARCHY"
	git -C "$OMARCHY" remote add origin "$OMARCHY_REPO"
	git -C "$OMARCHY" sparse-checkout set "$OMARCHY_RECIPE"
	git -C "$OMARCHY" fetch -q --depth 1 --filter=blob:none origin "$OMARCHY_COMMIT"
	git -C "$OMARCHY" -c advice.detachedHead=false checkout -q FETCH_HEAD
fi
[[ $(git -C "$OMARCHY" rev-parse HEAD) == "$OMARCHY_COMMIT" ]] ||
	die "omarchy-pkgs is not at $OMARCHY_COMMIT"
git -C "$OMARCHY" diff --quiet HEAD -- || die "omarchy-pkgs checkout has local changes"
RECIPE=$OMARCHY/$OMARCHY_RECIPE

# The kernel patches in the recipe's source order, as its prepare() applies them, and the
# kernel tarball it applies them to, which must be the one ./sources pins.
RECIPE_INFO=$(pkgbuild_info "$RECIPE") || die "cannot read $RECIPE/PKGBUILD"
mapfile -t OMARCHY_PATCHES < <(sed -n 's/^patch //p' <<<"$RECIPE_INFO")
[[ ${#OMARCHY_PATCHES[@]} -gt 0 ]] || die "no patches found in the Omarchy recipe"
[[ $(sed -n 's/^pkgver //p' <<<"$RECIPE_INFO") == "$KERNEL_VERSION" ]] ||
	die "the recipe builds $(sed -n 's/^pkgver //p' <<<"$RECIPE_INFO"), sources says KERNEL_VERSION=$KERNEL_VERSION"
[[ -z $(sed -n 's/^rcpatch //p' <<<"$RECIPE_INFO") ]] ||
	die "the recipe applies a release-candidate patch ($(sed -n 's/^rcpatch //p' <<<"$RECIPE_INFO")), which build.sh does not"
[[ $(sed -n 's/^tarball //p' <<<"$RECIPE_INFO") == "${KERNEL_URL##*/} $KERNEL_SHA256" ]] ||
	die "the recipe's kernel tarball ($(sed -n 's/^tarball //p' <<<"$RECIPE_INFO")) is not ${KERNEL_URL##*/} $KERNEL_SHA256 from sources"

# --- Kernel tree ---------------------------------------------------------------------------
msg "Extracting linux-$KERNEL_VERSION"
rm -rf "$SRC"
tar -C "$BUILD" -xf "$DL/${KERNEL_URL##*/}"
[[ -d $SRC ]] || die "tarball did not unpack to $SRC"

msg "Applying ${#OMARCHY_PATCHES[@]} Omarchy patches"
for p in "${OMARCHY_PATCHES[@]}"; do
	apply_patch "$SRC" "$RECIPE/$p" || die "Omarchy patch $p failed"
done
shopt -s nullglob
UBUNTU_PATCHES=("$REPO"/patches/ubuntu/*.patch)
shopt -u nullglob
msg "Applying ${#UBUNTU_PATCHES[@]} patches/ubuntu patches"
for p in "${UBUNTU_PATCHES[@]}"; do
	apply_patch "$SRC" "$p" || die "patch ${p##*/} failed"
done

# --- Config --------------------------------------------------------------------------------
msg "Configuring: Ubuntu's linux-nvidia config + config/n1x.config"
dpkg-deb --fsys-tarfile "$DL/${BASE_CONFIG_URL##*/}" | tar -xO "./$BASE_CONFIG_PATH" >"$BUILD/base.config"
verify_sha256 "$BUILD/base.config" "$BASE_CONFIG_FILE_SHA256"
cp "$BUILD/base.config" "$SRC/.config"
(cd "$SRC" && ARCH=arm64 scripts/kconfig/merge_config.sh -m -O . .config "$REPO/config/n1x.config" >/dev/null)
make -C "$SRC" -s ARCH=arm64 olddefconfig
bash "$REPO/scripts/config-check.sh" "$REPO/config/n1x.config" "$SRC/.config"

if [[ $PREPARE_ONLY -eq 1 ]]; then
	msg "Prepared $SRC ($RELEASE); stopping (--prepare-only)"
	exit 0
fi

# --- Kernel packages -----------------------------------------------------------------------
msg "Building kernel packages"
rm -f "$BUILD"/linux-*.deb "$BUILD"/linux-*.buildinfo "$BUILD"/linux-*.changes
# No linux-image-*-dbg package: it would hold every module's debug info (gigabytes).
DEB_BUILD_PROFILES=pkg.linux-n1x.nokerneldbg \
	make -C "$SRC" -j"$JOBS" ARCH=arm64 LOCALVERSION="-n1x$N1X_REVISION" \
	KDEB_PKGVERSION="$RELEASE" KDEB_SOURCENAME=linux-n1x bindeb-pkg
[[ $(make -C "$SRC" -s LOCALVERSION="-n1x$N1X_REVISION" kernelrelease) == "$RELEASE" ]] ||
	die "kernel release is not $RELEASE"

# --- NVIDIA --------------------------------------------------------------------------------
NVTEST=()
[[ $NVIDIA_TEST -eq 1 ]] && NVTEST=(--test-kernel "$SRC")
bash "$REPO/scripts/nvidia-dkms.sh" --tarball "$DL/${NVIDIA_URL##*/}" --out "$BUILD" --jobs "$JOBS" "${NVTEST[@]}"

# --- Output --------------------------------------------------------------------------------
rm -f "$OUT"/*.deb "$OUT"/SHA256SUMS "$OUT"/SOURCE
cp "$BUILD"/linux-image-"$RELEASE"_*.deb "$BUILD"/linux-headers-"$RELEASE"_*.deb \
	"$BUILD"/nvidia-n1x-dkms-*.deb "$OUT"/
printf 'https://github.com/bsneed/n1x-kernel-ubuntu commit %s\n' "$COMMIT" >"$OUT/SOURCE"
(cd "$OUT" && sha256sum ./*.deb >SHA256SUMS)
msg "Done: $OUT"
cat "$OUT/SHA256SUMS"
