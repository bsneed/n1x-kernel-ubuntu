#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - health check of the N1x kernel, USB4 and NVIDIA. Read-only, runs as your user.
#
# Why: one place to see that the running kernel is ours, the USB4 host routers are bound,
# a dock is enumerated and authorized, the NVIDIA modules match the user space, and what
# scripts/install.sh set up (apt pin, nvidia-persistenced override) is in place, and on the
# ProArt P16 that i2c-hid has patches/ubuntu/0002 (its probe retry).
# Prints one line per item: OK, WARN or FAIL (as proart-p16-linux's tools/check.sh does).
# Remove: nothing to remove; it only reads.
# Run with: bash scripts/check.sh
set -uo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/grub.sh"
. "$(dirname "$0")/lib-nvidia.sh"
. "$(dirname "$0")/lib-i2c-hid.sh"
load_sources
RELEASE=$(kernel_release "$KERNEL_VERSION" "$N1X_REVISION")

ok=0 warn=0 fail=0
OK() { printf '  \e[32mOK  \e[0m %s\n' "$*"; ok=$((ok + 1)); }
WARN() { printf '  \e[33mWARN\e[0m %s\n' "$*"; warn=$((warn + 1)); }
FAIL() { printf '  \e[31mFAIL\e[0m %s\n' "$*"; fail=$((fail + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then OK "$1"; else ${3:-FAIL} "$1"; fi; }

echo "== Kernel"
k=$(uname -r)
if [[ $k == "$RELEASE" ]]; then OK "running $k"; else FAIL "running $k, not $RELEASE"; fi
for p in "${N1X_PCI_OPTS[@]}"; do
	check "kernel parameter pci=...$p" "grep -Eq '(^| )pci=([^ ]*,)?$p(,| |\$)' /proc/cmdline"
done
check "suspend-to-idle is the default sleep (Omarchy 1113)" 'grep -q "\[s2idle\]" /sys/power/mem_sleep'
if [[ -n $(journalctl -k -b -n1 --no-pager -q 2>/dev/null) ]]; then
	check "power_wrap keeps the USB4 resources (Omarchy 1112)" \
		'! journalctl -k -b --no-pager -o cat | grep -q "SSPM released usb4 resources"'
else
	WARN "cannot read the kernel journal, so power_wrap is unchecked (sudo, or join the adm group)"
fi

echo "== USB4 / Thunderbolt"
check "thunderbolt_platform driver loaded (CONFIG_USB4_PLATFORM_NHI)" 'test -d /sys/module/thunderbolt_platform'
shopt -s nullglob
bound=(/sys/bus/platform/drivers/thunderbolt-platform/NVDA8100:*)
domains=(/sys/bus/thunderbolt/devices/domain*)
devices=(/sys/bus/thunderbolt/devices/[0-9]*-[1-9]*)
shopt -u nullglob
if [[ ${#bound[@]} -gt 0 ]]; then OK "${#bound[@]} USB4 host interface(s) NVDA8100 bound"
else FAIL "no NVDA8100 USB4 host interface bound"; fi
if [[ ${#domains[@]} -gt 0 ]]; then OK "${#domains[@]} Thunderbolt domain(s)"
else FAIL "no Thunderbolt domain in /sys/bus/thunderbolt/devices"; fi
check "IOMMU DMA protection reported (Bolt authorizes docks itself, Omarchy 1087-1089)" \
	'grep -q 1 /sys/bus/thunderbolt/devices/domain*/iommu_dma_protection' WARN
for d in /sys/bus/thunderbolt/devices/[0-9]*-[0-9]*; do
	[[ -r $d/device_name ]] || continue
	[[ $(basename "$d") == *-0 ]] && continue # host routers
	name="$(cat "$d/vendor_name" 2>/dev/null) $(cat "$d/device_name" 2>/dev/null)"
	speed="$(cat "$d/rx_speed" 2>/dev/null) x$(cat "$d/rx_lanes" 2>/dev/null)"
	if [[ $(cat "$d/authorized" 2>/dev/null) == 1 ]]; then
		OK "device $(basename "$d"): $name, authorized, $speed"
	else
		FAIL "device $(basename "$d"): $name, NOT authorized (boltctl enroll --policy auto <uuid>)"
	fi
done
[[ ${#devices[@]} -gt 0 ]] || WARN "no USB4/Thunderbolt device attached"
command -v boltctl >/dev/null && check "boltd answers (boltctl list)" 'boltctl list' WARN

echo "== NVIDIA"
want=$NVIDIA_VERSION
nvver=$(cat /sys/module/nvidia/version 2>/dev/null)
if [[ $nvver == "$want" ]]; then OK "nvidia module $nvver loaded"
else FAIL "nvidia module '${nvver:-not loaded}', want $want"; fi
check "nvidia module from DKMS nvidia-n1x/$want" "modinfo -n nvidia | grep -q /updates/dkms/ && dkms status -m nvidia-n1x -v $want -k $k | grep -q installed"
# The kernel loads nvidia*.ko from the initramfs (nvidia-kernel-common's framebuffer-nvidia
# hook), so a module rebuilt after the initramfs, or after this boot, is not the one running.
ko=$(modinfo -n nvidia 2>/dev/null)
loaded=$(cat /sys/module/nvidia/srcversion 2>/dev/null)
if [[ -f $ko && -n $loaded ]]; then
	if [[ $loaded == "$(modinfo -F srcversion nvidia 2>/dev/null)" ]]; then
		OK "running nvidia module is the installed one (srcversion $loaded)"
	elif [[ $(stat -c %Y "$ko") -gt $(awk '/^btime/{print $2}' /proc/stat) ]]; then
		WARN "nvidia module rebuilt after this boot: reboot to load it"
	else
		FAIL "running nvidia module is not the installed one: the initramfs holds another (sudo update-initramfs -u -k $k, reboot)"
	fi
fi
B=${want%%.*}
uver=$(dpkg-query -W -f '${Version}' "nvidia-utils-$B" 2>/dev/null)
note=""
[[ $uver == "$NVIDIA_UBUNTU_VERSION" ]] || note=", validated with $NVIDIA_UBUNTU_VERSION"
if [[ $uver == "$want"-* ]]; then
	OK "user space $uver (nvidia-utils-$B)$note"
else
	FAIL "user space '${uver:-not installed}' (nvidia-utils-$B), want $want-*"
fi
check "nvidia-smi ($(nvidia-smi --query-gpu=name,driver_version,pstate --format=csv,noheader 2>/dev/null))" 'nvidia-smi -L'
cand=$(apt-cache policy "nvidia-utils-$B" 2>/dev/null | sed -n 's/^ *Candidate: //p')
if [[ ! -f /etc/apt/preferences.d/n1x-kernel-ubuntu-nvidia ]]; then
	FAIL "no apt pin (/etc/apt/preferences.d/n1x-kernel-ubuntu-nvidia): apt may move NVIDIA off $want"
elif [[ $cand != "$want"-* ]]; then
	FAIL "apt pin does not hold NVIDIA at $want: apt would install nvidia-utils-$B ${cand:-(none)}"
elif [[ $cand != "$uver" ]]; then
	WARN "apt pin holds NVIDIA at $want; an Ubuntu update of it is waiting: $cand (sudo apt upgrade)"
else
	OK "apt pin holds NVIDIA at $want (apt's candidate is the installed $cand)"
fi
nodkms=$(for b in /lib/modules/*/build; do
	kk=${b%/build} kk=${kk##*/}
	dkms status -m nvidia-n1x -v "$want" -k "$kk" 2>/dev/null | grep -q installed || echo "$kk"
done | tr '\n' ' ')
if [[ -z $nodkms ]]; then OK "NVIDIA modules built for every kernel with headers"
else WARN "no NVIDIA modules for: $nodkms"; fi

if [[ -r $PERSISTENCED_UNIT ]]; then
	s=$(persistenced_status "$PERSISTENCED_UNIT" "$PERSISTENCED_OVERRIDE")
	"${s%% *}" "${s#* }"
fi

if is_proart_p16; then
	echo "== Keyboard and touchpad (ProArt P16, docs/i2c-hid-probe-retry.md)"
	s=$(i2c_hid_retry_status "$(modinfo -n i2c_hid 2>/dev/null)" "$(cat /sys/module/i2c_hid/srcversion 2>/dev/null)" \
		"$(modinfo -F srcversion i2c_hid 2>/dev/null)" "$k")
	"${s%% *}" "${s#* }"
fi

echo "== Displays"
for c in /sys/class/drm/card*-*; do
	[[ -r $c/status ]] || continue
	s=$(cat "$c/status")
	[[ $s == connected ]] || continue
	modes=$(wc -l <"$c/modes" 2>/dev/null)
	OK "${c##*/card[0-9]-} connected, $modes modes, first $(head -1 "$c/modes" 2>/dev/null)"
done

echo
echo "Result: $ok OK, $warn WARN, $fail FAIL"
[[ $fail -eq 0 ]]
