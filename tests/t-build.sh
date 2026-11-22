# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib-build.sh: reading Omarchy's PKGBUILD, the checkout commit, the DKMS templates.
# Sourced by tests/run.sh, which defines eq, fails, skip, $T, $P and $OSI.
# shellcheck shell=bash
. scripts/lib-build.sh

# --- Omarchy's PKGBUILD (a fixture shaped like linux-omarchy-aarch64's) -------------------------
mkdir -p "$T/recipe"
cat >"$T/recipe/PKGBUILD" <<'PKG'
pkgver=7.3
pkgrel=75
_major=${pkgver%%.*}
if [[ $pkgver == *rc* ]]; then
  _base=${pkgver%rc*}
  _prev=${_base%.*}.$(( ${_base##*.} - 1 ))
  _srcname=linux-${_prev%.0}
  _rcpatch=patch-${pkgver//rc/-rc}
else
  _srcname=linux-$pkgver
fi
echo "noise on stdout"
source=(
  https://cdn.kernel.org/pub/linux/kernel/v${_major}.x/${_srcname}.tar.{xz,sign}
  ${_rcpatch:+https://cdn.kernel.org/pub/linux/kernel/v${_major}.x/stable-review/${_rcpatch}.xz}
  0010-archlinux-base.patch{,.sig}
  0110-bore-7.0.0.patch.zst
  renamed-1070-usb4.patch::https://example.org/download/1070
  nvidia-0003-oled.patch
  config.aarch64
  1112-power-wrap.patch
)
sha256sums=('87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953'
            'SKIP' '1111' 'SKIP' '2222' '3333' '4444' '5555' '6666')
PKG
pkgbuild_info "$T/recipe" >"$T/pkginfo"
eq "pkgbuild: version" "pkgver 7.3" "$(grep '^pkgver ' "$T/pkginfo")"
eq "pkgbuild: no rc patch" "rcpatch " "$(grep '^rcpatch' "$T/pkginfo")"
eq "pkgbuild: tarball and its sha256" "tarball linux-7.3.tar.xz 87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953" \
	"$(grep '^tarball ' "$T/pkginfo")"
eq "pkgbuild: patches in order, .zst and :: handled, nvidia-* left out" \
	"0010-archlinux-base.patch 0110-bore-7.0.0.patch renamed-1070-usb4.patch 1112-power-wrap.patch" \
	"$(sed -n 's/^patch //p' "$T/pkginfo" | paste -sd' ')"
sed -i.bak 's/^pkgver=7.3$/pkgver=7.4rc3/' "$T/recipe/PKGBUILD"
pkgbuild_info "$T/recipe" >"$T/pkginfo"
eq "pkgbuild rc: version" "pkgver 7.4rc3" "$(grep '^pkgver ' "$T/pkginfo")"
eq "pkgbuild rc: rc patch" "rcpatch patch-7.4-rc3" "$(grep '^rcpatch' "$T/pkginfo")"
eq "pkgbuild rc: tarball of the previous release" "tarball linux-7.3.tar.xz 87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953" \
	"$(grep '^tarball ' "$T/pkginfo")"
printf 'pkgver=7.3\nsource=(\n' >"$T/recipe/PKGBUILD"
fails "pkgbuild that does not parse" pkgbuild_info "$T/recipe"
fails "pkgbuild missing" pkgbuild_info "$T/no-recipe"

# --- the checkout's commit ----------------------------------------------------------------------
if command -v git >/dev/null; then
	R=$T/repo
	git init -q "$R" && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m t
	head=$(git -C "$R" rev-parse HEAD)
	eq "commit of a clean checkout" "$head" "$(REPO=$R source_commit)"
	touch "$R/new"
	eq "commit with an untracked file" "$head-dirty" "$(REPO=$R source_commit)"
	# shellcheck disable=SC2016 # expanded by the inner bash
	fails "commit outside a checkout" env REPO="$T/recipe" bash -c '. scripts/lib.sh; . scripts/lib-build.sh; REPO=$1 source_commit' _ "$T/recipe"
else
	skip "source_commit" "no git"
fi

# --- the DKMS package templates (nvidia-dkms/) ---------------------------------------------------
NVIDIA_VERSION=620.73.04 BRANCH=620 DEB_VERSION=620.73.04-n1x2 SIZE=12345
dkms_subst nvidia-dkms/control >"$T/control"
eq "control: no placeholder left" "" "$(grep -o '@[A-Z_]*@' "$T/control")"
eq "control: version" "Version: 620.73.04-n1x2" "$(grep '^Version:' "$T/control")"
eq "control: any Ubuntu revision of 620.73.04, as nvidia-driver-620-open's range" \
	"Depends: dkms, nvidia-kernel-common-620 (>= 620.73.04), nvidia-kernel-common-620 (<= 620.73.04-1)" \
	"$(grep '^Depends:' "$T/control")"
eq "control: provides what nvidia-driver-620-open depends on" \
	"Provides: nvidia-dkms-kernel, nvidia-dkms-620-open (= 620.73.04)" "$(grep '^Provides:' "$T/control")"
eq "control: size" "Installed-Size: 12345" "$(grep '^Installed-Size:' "$T/control")"
if command -v dpkg >/dev/null; then
	for v in 620.73.04-0ubuntu0.26.04.1 620.73.04-0ubuntu0.26.04.7; do
		eq "control: takes nvidia-kernel-common-620 $v" yes \
			"$(dpkg --compare-versions "$v" ge 620.73.04 && dpkg --compare-versions "$v" le 620.73.04-1 && echo yes)"
	done
	for v in 620.73.05-0ubuntu0.26.04.1 620.73.03-0ubuntu1 620.80.01-0ubuntu0.26.04.1; do
		eq "control: refuses nvidia-kernel-common-620 $v" no \
			"$(dpkg --compare-versions "$v" ge 620.73.04 && dpkg --compare-versions "$v" le 620.73.04-1 && echo yes || echo no)"
	done
else
	skip "control version range" "no dpkg"
fi
dkms_subst nvidia-dkms/dkms.conf >"$T/dkms.conf"
eq "dkms.conf: version" 'PACKAGE_VERSION="620.73.04"' "$(grep '^PACKAGE_VERSION=' "$T/dkms.conf")"
for s in postinst prerm postrm; do
	dkms_subst "nvidia-dkms/$s" >"$T/$s"
	eq "$s: no placeholder left" "" "$(grep -o '@[A-Z_]*@' "$T/$s")"
	eq "$s: sh -n" 0 "$(sh -n "$T/$s" 2>&1; echo $?)"
	if command -v shellcheck >/dev/null; then
		eq "$s: shellcheck" "" "$(shellcheck -s sh "$T/$s" 2>&1)"
	else
		skip "$s: shellcheck" "no shellcheck"
	fi
done
eq "postinst refreshes every initramfs" 1 "$(grep -c 'update-initramfs -u -k all' "$T/postinst")"
eq "prerm removes this version" 1 "$(grep -c 'dkms remove -m nvidia-n1x -v 620.73.04 --all' "$T/prerm")"
unset NVIDIA_VERSION BRANCH DEB_VERSION SIZE
