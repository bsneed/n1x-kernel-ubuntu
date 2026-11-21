#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - build the nvidia-n1x-dkms-<branch>-open .deb
#
# Why: Omarchy's NVIDIA N1x fixes (patches/nvidia) change nvkms and the DisplayPort library,
# which Ubuntu's nvidia-dkms-*-open package only ships as NVIDIA's prebuilt object files. This
# packages NVIDIA's full open-gpu-kernel-modules source with those patches as a DKMS module
# (nvidia-dkms/), which stands in for Ubuntu's nvidia-dkms-<branch>-open next to Ubuntu's own
# NVIDIA user space of the same version. With --test-kernel it also builds the modules once
# against a built kernel tree, so a patch or kernel API break fails the build here.
# Remove: rm build/nvidia-n1x-dkms-*.deb
# Run with: bash scripts/nvidia-dkms.sh --tarball FILE --out DIR [--jobs N] [--test-kernel KSRC]
#           (scripts/build.sh runs it)
set -euo pipefail
. "$(dirname "$0")/lib.sh"

TARBALL='' OUTDIR='' JOBS=$(nproc) TEST_KERNEL=''
while [[ $# -gt 0 ]]; do
	case $1 in
	--tarball) TARBALL=$2; shift 2 ;;
	--out) OUTDIR=$2; shift 2 ;;
	--jobs) JOBS=$2; shift 2 ;;
	--test-kernel) TEST_KERNEL=$2; shift 2 ;;
	*) die "unknown option $1" ;;
	esac
done
[[ -f $TARBALL && -d $OUTDIR ]] || die "usage: $0 --tarball FILE --out DIR [--test-kernel KSRC]"
load_sources
verify_sha256 "$TARBALL" "$NVIDIA_SHA256"

BRANCH=${NVIDIA_VERSION%%.*}
NAME=nvidia-n1x
PKG=nvidia-n1x-dkms-$BRANCH-open
DEB_VERSION=$NVIDIA_VERSION-n1x$NVIDIA_N1X_REVISION
WORK=$OUTDIR/nvidia-dkms
TREE=$WORK/root/usr/src/$NAME-$NVIDIA_VERSION

msg "Preparing $PKG $DEB_VERSION"
rm -rf "$WORK"
mkdir -p "$WORK/root/usr/src" "$WORK/root/DEBIAN" "$WORK/root/usr/share/doc/$PKG"
tar -C "$WORK/root/usr/src" -xf "$TARBALL"
mv "$WORK/root/usr/src/NVIDIA-kernel-module-source-$NVIDIA_VERSION" "$TREE"
for p in "$REPO"/patches/nvidia/*.patch; do
	patch -d "$TREE" -p1 --batch --fuzz=0 --quiet <"$p" || die "NVIDIA patch ${p##*/} failed"
done

# For reproducible builds, as Arch's and Omarchy's nvidia-open-dkms do.
sed -i -e 's/^  HOSTNAME.*/  HOSTNAME = echo n1x-kernel-ubuntu/' \
	-e 's/^WHOAMI.*/WHOAMI = echo n1x-kernel-ubuntu/' \
	-e 's/^DATE.*/DATE = date -r version.mk/' "$TREE/utils.mk"

subst() {
	sed -e "s/@NVIDIA_VERSION@/$NVIDIA_VERSION/g" -e "s/@NVIDIA_BRANCH@/$BRANCH/g" \
		-e "s/@NVIDIA_UBUNTU_VERSION@/$NVIDIA_UBUNTU_VERSION/g" \
		-e "s/@DEB_VERSION@/$DEB_VERSION/g" -e "s/@INSTALLED_SIZE@/${SIZE:-0}/g" "$1"
}
subst "$REPO/nvidia-dkms/dkms.conf" >"$TREE/dkms.conf"
mkdir -p "$TREE/patches"
cp "$REPO"/nvidia-dkms/patches/*.patch "$TREE/patches/"
cp "$REPO"/patches/nvidia/*.patch "$TREE/patches/" # for reference; already applied
cp "$TREE/COPYING" "$WORK/root/usr/share/doc/$PKG/copyright"

if [[ -n $TEST_KERNEL ]]; then
	msg "Test-building the NVIDIA modules against $TEST_KERNEL"
	rm -rf "$WORK/test"
	cp -a "$TREE" "$WORK/test"
	make -C "$WORK/test" -j"$JOBS" modules SYSSRC="$TEST_KERNEL" SYSOUT="$TEST_KERNEL" \
		IGNORE_PREEMPT_RT_PRESENCE=1 >"$WORK/test.log" 2>&1 ||
		{ tail -50 "$WORK/test.log"; die "NVIDIA modules do not build against $TEST_KERNEL"; }
	for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm nvidia-peermem; do
		[[ -f $WORK/test/kernel-open/$m.ko ]] || die "test build made no $m.ko"
	done
	modinfo -F vermagic "$WORK/test/kernel-open/nvidia.ko"
	rm -rf "$WORK/test"
fi

SIZE=$(du -sk "$WORK/root" | cut -f1)
subst "$REPO/nvidia-dkms/control" >"$WORK/root/DEBIAN/control"
for s in postinst prerm postrm; do
	subst "$REPO/nvidia-dkms/$s" >"$WORK/root/DEBIAN/$s"
	chmod 755 "$WORK/root/DEBIAN/$s"
done
rm -f "$OUTDIR/${PKG}_"*.deb
dpkg-deb --root-owner-group -Zxz --build "$WORK/root" "$OUTDIR/${PKG}_${DEB_VERSION}_arm64.deb" >/dev/null
msg "Built $OUTDIR/${PKG}_${DEB_VERSION}_arm64.deb"
rm -rf "$WORK"
