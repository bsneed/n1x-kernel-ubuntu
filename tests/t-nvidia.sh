# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib-nvidia.sh: NVIDIA package selection, the apt pin and the persistenced override.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash
. scripts/lib-nvidia.sh

# A ProArt P16 after proart-p16-linux (615) plus Docker with GPU access, as dpkg-query lists it.
cat >"$T/installed" <<'PKGS'
libnvidia-cfg1-615=615.71.09-0ubuntu0.26.04.2
libnvidia-common-615=615.71.09-0ubuntu0.26.04.2
libnvidia-compute-615=615.71.09-0ubuntu0.26.04.2
libnvidia-container-tools=1.17.8-1
libnvidia-container1=1.17.8-1
libnvidia-egl-wayland1=1:1.1.20-1
libnvidia-fbc1-615=615.71.09-0ubuntu0.26.04.2
libnvidia-gl-615=615.71.09-0ubuntu0.26.04.2
linux-modules-nvidia-615-open-7.0.0-1026-nvidia=7.0.0-1026.27
linux-modules-nvidia-615-open-nvidia=7.0.0-1026.27
linux-objects-nvidia-615-open-7.0.0-1026-nvidia=7.0.0-1026.27
linux-signatures-nvidia-7.0.0-1026-nvidia=7.0.0-1026.27
nvidia-compute-utils-615=615.71.09-0ubuntu0.26.04.2
nvidia-container-toolkit=1.17.8-1
nvidia-container-toolkit-base=1.17.8-1
nvidia-cuda-toolkit=12.9.1-1ubuntu1
nvidia-driver-615-open=615.71.09-0ubuntu0.26.04.2
nvidia-firmware-615-615.71.09=615.71.09-0ubuntu0.26.04.2
nvidia-headless-no-dkms-615-open=615.71.09-0ubuntu0.26.04.2
nvidia-kernel-common-615=615.71.09-0ubuntu0.26.04.2
nvidia-kernel-source-615-open=615.71.09-0ubuntu0.26.04.2
nvidia-modprobe=580.95.05-1
nvidia-prime=0.8.17.2
nvidia-settings=580.95.05-1
nvidia-utils-615=615.71.09-0ubuntu0.26.04.2
nvidia-vaapi-driver=0.0.14-1
nvidia-server-utils-580-server=580.95.05-0ubuntu1
xserver-xorg-video-nvidia-615=615.71.09-0ubuntu0.26.04.2
nvidia-dkms-620-open=620.73.04-0ubuntu0.26.04.1
nvidia-kernel-common-620=620.73.04-0ubuntu0.26.04.1
nvidia-firmware-620-620.73.04=620.73.04-0ubuntu0.26.04.1
nvidia-utils-620=620.73.04-0ubuntu0.26.04.1
nvidia-n1x-dkms-620-open=620.73.04-n1x1
xserver-xorg-video-nvidia-620=620.73.04-0ubuntu0.26.04.1
PKGS
nvidia_other_versions 620 nvidia-n1x-dkms-620-open <"$T/installed" >"$T/other"
eq "other versions: the 615 stack, the 580 server utils and Ubuntu's 620 DKMS" \
	"libnvidia-cfg1-615 libnvidia-common-615 libnvidia-compute-615 libnvidia-fbc1-615 libnvidia-gl-615 linux-modules-nvidia-615-open-7.0.0-1026-nvidia linux-modules-nvidia-615-open-nvidia linux-objects-nvidia-615-open-7.0.0-1026-nvidia nvidia-compute-utils-615 nvidia-driver-615-open nvidia-firmware-615-615.71.09 nvidia-headless-no-dkms-615-open nvidia-kernel-common-615 nvidia-kernel-source-615-open nvidia-utils-615 nvidia-server-utils-580-server xserver-xorg-video-nvidia-615 nvidia-dkms-620-open" \
	"$(paste -sd' ' "$T/other")"
for keep in nvidia-settings nvidia-prime nvidia-container-toolkit nvidia-container-toolkit-base \
	libnvidia-container1 libnvidia-container-tools nvidia-cuda-toolkit nvidia-modprobe \
	nvidia-vaapi-driver libnvidia-egl-wayland1 linux-signatures-nvidia-7.0.0-1026-nvidia \
	nvidia-kernel-common-620 nvidia-utils-620 nvidia-firmware-620-620.73.04 \
	xserver-xorg-video-nvidia-620 nvidia-n1x-dkms-620-open; do
	eq "other versions keep $keep" "" "$(grep -x "$keep" "$T/other")"
done
eq "other versions of nothing" "" "$(nvidia_other_versions 620 nvidia-n1x-dkms-620-open </dev/null)"
eq "other versions of another branch" "nvidia-utils-620 nvidia-dkms-615-open" \
	"$(printf 'nvidia-utils-620=1\nnvidia-utils-615=1\nnvidia-dkms-615-open=1\n' |
		nvidia_other_versions 615 nvidia-n1x-dkms-615-open | paste -sd' ')"
eq "other versions: Ubuntu's closed DKMS too" "nvidia-dkms-620" \
	"$(printf 'nvidia-dkms-620=1\n' | nvidia_other_versions 620 nvidia-n1x-dkms-620-open)"
eq "branch of nvidia-utils-615" 615 "$(nvidia_branch_of nvidia-utils-615)"
eq "branch of libnvidia-fbc1-620" 620 "$(nvidia_branch_of libnvidia-fbc1-620)"
eq "branch of the 580 server driver" 580 "$(nvidia_branch_of nvidia-driver-580-server-open)"
eq "branch of the 615 firmware" 615 "$(nvidia_branch_of nvidia-firmware-615-615.71.09)"
eq "branch of prebuilt modules" 615 "$(nvidia_branch_of linux-modules-nvidia-615-open-7.0.0-1026-nvidia)"
eq "branch of the X driver" 620 "$(nvidia_branch_of xserver-xorg-video-nvidia-620)"
fails "no branch for nvidia-settings" nvidia_branch_of nvidia-settings
fails "no branch for libnvidia-container1" nvidia_branch_of libnvidia-container1
fails "no branch for linux-signatures-nvidia" nvidia_branch_of linux-signatures-nvidia-7.0.0-1026-nvidia
fails "no branch for a 4-digit number" nvidia_branch_of nvidia-foo-1234
eq "prebuilt kernel" 7.0.0-1026-nvidia "$(nvidia_prebuilt_kernel linux-modules-nvidia-615-open-7.0.0-1026-nvidia)"
eq "prebuilt kernel of a server build" 7.0.0-44-generic "$(nvidia_prebuilt_kernel linux-modules-nvidia-580-server-7.0.0-44-generic)"
fails "prebuilt kernel of user space" nvidia_prebuilt_kernel nvidia-utils-615
eq "prebuilt kernel of the objects package" 7.0.0-1026-nvidia "$(nvidia_prebuilt_kernel linux-objects-nvidia-615-open-7.0.0-1026-nvidia)"
eq "prebuilt kernel of a -64k kernel" 7.0.0-1026-nvidia-64k "$(nvidia_prebuilt_kernel linux-modules-nvidia-615-open-7.0.0-1026-nvidia-64k)"
fails "no prebuilt kernel for the metapackage" nvidia_prebuilt_kernel linux-modules-nvidia-615-open-nvidia
fails "no prebuilt kernel for the -64k metapackage" nvidia_prebuilt_kernel linux-modules-nvidia-615-open-nvidia-64k

# --- --remove: what goes, and what comes back --------------------------------------------------
grep -E -- '-615|=615' "$T/installed" >"$T/before"
nvidia_restore_removals 620 nvidia-n1x-dkms-620-open "$T/before" <"$T/installed" >"$T/restore-rm"
eq "restore removes 620 and ours" \
	"nvidia-dkms-620-open nvidia-kernel-common-620 nvidia-firmware-620-620.73.04 nvidia-utils-620 nvidia-n1x-dkms-620-open xserver-xorg-video-nvidia-620" \
	"$(paste -sd' ' "$T/restore-rm")"
eq "restore keeps a 620 package that was there before" "nvidia-kernel-common-620 nvidia-n1x-dkms-620-open" \
	"$(printf 'nvidia-utils-620=1\nnvidia-kernel-common-620=1\nnvidia-n1x-dkms-620-open=1\n' |
		nvidia_restore_removals 620 nvidia-n1x-dkms-620-open <(printf 'nvidia-utils-620=1\n') | paste -sd' ')"
# The round trip on a machine that already ran Ubuntu's 620 (from -proposed): the install
# replaces only Ubuntu's DKMS package, and --remove must give back exactly what was there.
cat >"$T/had620" <<'PKGS'
nvidia-driver-620-open=620.73.04-0ubuntu0.26.04.1
nvidia-dkms-620-open=620.73.04-0ubuntu0.26.04.1
nvidia-kernel-common-620=620.73.04-0ubuntu0.26.04.1
nvidia-kernel-source-620-open=620.73.04-0ubuntu0.26.04.1
nvidia-utils-620=620.73.04-0ubuntu0.26.04.1
libnvidia-gl-620=620.73.04-0ubuntu0.26.04.1
nvidia-firmware-620-620.73.04=620.73.04-0ubuntu0.26.04.1
nvidia-settings=580.95.05-1
PKGS
nvidia_other_versions 620 nvidia-n1x-dkms-620-open <"$T/had620" >"$T/had620-replaced"
eq "had 620: the install replaces Ubuntu's DKMS package only" nvidia-dkms-620-open "$(cat "$T/had620-replaced")"
nvidia_before 620 nvidia-n1x-dkms-620-open "$T/had620-replaced" <"$T/had620" >"$T/had620-before"
eq "had 620: every 620 package is recorded, at its version" "$(grep -- '-620' "$T/had620")" "$(cat "$T/had620-before")"
# After the install: Ubuntu's DKMS package replaced by ours, the user space install.sh adds.
{ grep -v '^nvidia-dkms-620-open=' "$T/had620"
	printf '%s\n' nvidia-n1x-dkms-620-open=620.73.04-n1x2 nvidia-headless-no-dkms-620-open=620.73.04-0ubuntu0.26.04.1 \
		libnvidia-decode-620=620.73.04-0ubuntu0.26.04.1; } >"$T/had620-after"
eq "had 620: --remove takes away only what the install added" \
	"nvidia-n1x-dkms-620-open nvidia-headless-no-dkms-620-open libnvidia-decode-620" \
	"$(nvidia_restore_removals 620 nvidia-n1x-dkms-620-open "$T/had620-before" <"$T/had620-after" | paste -sd' ')"
eq "had 620: --remove reinstalls Ubuntu's DKMS package and keeps the rest" \
	"nvidia-driver-620-open nvidia-dkms-620-open nvidia-kernel-common-620 nvidia-kernel-source-620-open nvidia-utils-620 libnvidia-gl-620 nvidia-firmware-620-620.73.04" \
	"$(cut -d= -f1 "$T/had620-before" | paste -sd' ')"
# The usual case (615 before): only the 615 stack is recorded, never ours or unrelated packages.
nvidia_other_versions 620 nvidia-n1x-dkms-620-open <"$T/installed" >"$T/replaced"
eq "615 before: records what it replaces and the 620 packages there" \
	"$(grep -vE '^(nvidia-n1x-dkms-620-open|libnvidia-container|libnvidia-egl|linux-signatures|nvidia-(container|cuda|modprobe|prime|settings|vaapi))' "$T/installed")" \
	"$(nvidia_before 620 nvidia-n1x-dkms-620-open "$T/replaced" <"$T/installed")"
eq "nothing installed: nothing recorded" "" "$(nvidia_before 620 nvidia-n1x-dkms-620-open /dev/null </dev/null)"
eq "restore leaves the rest" "" \
	"$(printf 'nvidia-settings=1\nnvidia-utils-615=1\nlibnvidia-container1=1\n' |
		nvidia_restore_removals 620 nvidia-n1x-dkms-620-open /dev/null)"

# --- the apt pin -------------------------------------------------------------------------------
nvidia_pin_text 620 620.73.04 >"$T/pin"
eq "pin holds any Ubuntu revision of 620.73.04" "Pin: version 620.73.04-*" "$(grep -x 'Pin: version 620.73.04-\*' "$T/pin")"
eq "pin blocks Ubuntu's DKMS package" "Package: nvidia-dkms-620-open|Pin: version *|Pin-Priority: -1" \
	"$(grep -A2 -x 'Package: nvidia-dkms-620-open' "$T/pin" | paste -sd'|')"
eq "pin has two stanzas" 2 "$(grep -c '^Package:' "$T/pin")"
eq "user-space-only pin" "Package: /^(lib)?nvidia-.*-620(-open|-server)?$/ /^nvidia-firmware-620-/ xserver-xorg-video-nvidia-620|Pin: version 620.73.04-*|Pin-Priority: 1001" \
	"$(nvidia_pin_text 620 620.73.04 user-space-only | grep -v '^#' | paste -sd'|')"
re=$(sed -n 's|^Package: /\(.*\)/ /.*|\1|p' "$T/pin")
for p in nvidia-headless-no-dkms-620-open nvidia-utils-620 libnvidia-gl-620 libnvidia-fbc1-620 \
	nvidia-kernel-common-620 nvidia-compute-utils-620 nvidia-kernel-source-620-open; do
	eq "pin covers $p" yes "$([[ $p =~ $re ]] && echo yes)"
done
for p in nvidia-utils-615 nvidia-settings libnvidia-container1 nvidia-utils-6200; do
	eq "pin leaves $p" no "$([[ $p =~ $re ]] && echo yes || echo no)"
done
eq "prebuilt kernel of a server-open build" 7.0.0-44-generic "$(nvidia_prebuilt_kernel linux-modules-nvidia-580-server-open-7.0.0-44-generic)"

# --- nvidia-persistenced override (fixture: nvidia-compute-utils-620 620.73.04's unit) ----------
U620=tests/fixtures/nvidia-persistenced-620.service
persistenced_override "$U620" >"$T/persistenced"
eq "override drops the Before= line" "" "$(grep -F 'Before=' "$T/persistenced" | grep -v '^#')"
eq "override is the unit otherwise" "$(grep -vxF "$PERSISTENCED_CYCLE" "$U620")" "$(grep -v '^#' "$T/persistenced")"
eq "override keeps the trailing blank line" "$(tail -c 2 "$U620" | od -An -c)" "$(tail -c 2 "$T/persistenced" | od -An -c)"
eq "override says what it is" "$PERSISTENCED_MARK (scripts/install.sh) from $U620:" "$(head -1 "$T/persistenced")"
eq "override says how to remove it" 1 "$(grep -c '^# Remove by hand: sudo rm /etc/systemd/system/nvidia-persistenced.service' "$T/persistenced")"
eq "override is ours" 0 "$(persistenced_is_ours "$T/persistenced"; echo $?)"
eq "the packaged unit is not ours" 1 "$(persistenced_is_ours "$U620"; echo $?)"
eq "a missing file is not ours" 1 "$(persistenced_is_ours "$T/none"; echo $?)"
grep -vxF "$PERSISTENCED_CYCLE" "$U620" >"$T/fixed.service"
fails "no override for a unit without the cycle" persistenced_override "$T/fixed.service"
eq "no output for a unit without the cycle" "" "$(persistenced_override "$T/fixed.service" 2>&1)"
fails "no override without the unit" persistenced_override "$T/none.service"
sed "s/^$PERSISTENCED_CYCLE\$/Before=systemd-backlight@backlight:nvidia_0.service other.service/" "$U620" >"$T/two.service"
fails "no override when the line differs" persistenced_override "$T/two.service"
