# TODO

Open work on n1x-kernel-ubuntu and the ASUS ProArt P16 (H7607BA, BIOS H7607BA.300) it was
validated on. Check items off here when they land; move anything that turns into a known
limitation into the README.

## Display

- [ ] **Dell U4025QW runs at 60 Hz through the CalDigit TS5 Plus.** Kernel 7.3.0-n1x1 with NVIDIA
  620 drives it (DP-8, USB4 DisplayPort tunnel) but offers 60 Hz at most. The same monitor, dock
  and cable run 5120x2160 at 120 Hz on a Mac, so the limit is on the N1x/Linux side. Check whether
  DSC is enabled through the tunnel, the tunnel's bandwidth allocation (link rate and lanes), and
  the driver's mode list against the EDID/DisplayID.
- [x] **Red and orange messages at boot** (2026-11-21). The coloured text was systemd's status
  lines, not the kernel (`quiet` keeps kernel messages off the console). Fixed on rtx24; after a
  reboot PID 1 logs no warnings:
  - Red `Dependency failed for sssd-*.socket` x6: sssd ships enabled with no `/etc/sssd/sssd.conf`.
    Fix: `systemctl disable sssd-{nss,autofs,pac,pam,ssh,sudo}.socket`. Plain Ubuntu, not ours.
  - Orange `sysinit.target: Found ordering cycle`: Ubuntu's `nvidia-compute-utils-620` orders
    `nvidia-persistenced` (after `sysinit.target`) `Before=systemd-backlight@backlight:nvidia_0`
    (before it). Fix: `/etc/systemd/system/nvidia-persistenced.service`, the packaged unit minus
    that line (an empty `Before=` drop-in can't reset the list).
  - Kernel side, journal only, all harmless: BIOS 300 firmware bugs (ACPI thermal "No valid trip
    points" x8, GICv3 illegal GSI2, arch_timer without EL2 virtual timer, ACPI `_STA` error on a
    PCIe NVMe slot), SoundWire probe deferral (-517), Cirrus dummy regulators, SMMU/MPAM/DMA-mask
    info.
- [x] **Ship the nvidia-persistenced override in `scripts/install.sh`** (2026-11-21): generated
  from the packaged unit on every run, removed by `--remove`, checked by `check.sh`.
- [ ] Report the nvidia-persistenced ordering cycle against Ubuntu's nvidia-graphics-drivers-620
  (`Before=systemd-backlight@backlight:nvidia_0.service` in a unit that runs after
  `sysinit.target`).
- [x] **README: AppArmor differs from stock Ubuntu** (2026-11-21, Known issues).
- [ ] **Dock hotplug is broken on the display side.** Seen 2026-11-21 on 7.3.0-n1x1 + NVIDIA 620:
  - Unplugging the dock does not fall back to the internal panel (eDP-1); the desktop stays on
    the absent external until the lid is closed and reopened.
  - Moving the dock to a different USB-C port brought no picture on the Dell, and tripped a
    kernel WARN in `nvidia_drm` (`__nv_drm_handle_flip_event+0x218` via `nv_drm_event_callback`
    / `nvKmsKapiHandleEventQueueChange`) that glitched GNOME. Back on the original port the Dell
    came up again. dmesg snapshot: rtx24 `/home/bsneed/work/replug-1628/`.
  - The dock's USB and 10GbE re-enumerate fine; it is only DisplayPort.
  - About six minutes after the replug, `NetworkManager`, `tailscaled` and kernel workers hung
    for over two minutes on a mutex held by `irq/315-pciehp` (PCIe hotplug), so the hotplug path
    can stall networking too.
  - See the DP 120 Hz report (`/Users/bsneed/work/n1x-kernel-ubuntu-reports/dp-120hz.md`) for
    which host router / DP IN adapter each port uses.

## Power and suspend

- [ ] **Unattended wake from s2idle.** Only the internal keyboard and the power button wake the
  P16. RTC alarms (rtc0; rtc1 returns EIO), Wake-on-LAN through the dock, USB devices on the dock
  and Wi-Fi WoWLAN do not. BIOS 300's DSDT gives the PCIe root ports (`RP0`) `_S0W 0x04` but no
  `_PRW` (see seankd3/asus-proart-p16-rtx-spark-linux#10). Try an SSDT override from the initramfs
  that adds `_PRW`, then retest Wi-Fi and dock wake.
- [ ] **BIOS update** once ASUS publishes something newer than H7607BA.300 for this model (none
  as of 2026-11-21). The BIOS-300 baseline (ACPI dump and both `check.sh` outputs) is in
  `/home/bsneed/work/bios-300-baseline/` on rtx24 and spark1. Diff the new tables for `_PRW`, then
  rerun the regression and wake tests.
- [ ] **Long-sleep audio test.** Suspend for 30+ minutes and check the mic, headphone jack and
  tweeters. If they die, try proart-p16-linux's `optional/sleep-audio.sh`.
- [ ] **Re-verify s2idle with patch 0010 revision 2** (`NVIDIA_N1X_REVISION=2`, scoped to
  10de:2e03/2e06/2e13): a real suspend/resume on rtx24 with the dock, as for revision 1.
- [ ] *(optional)* **615 without `RMSkipACPIBattCap` on AC**, for a definitive answer on
  NVIDIA/open-gpu-kernel-modules#1521. On 7.3 + 620 the override made no difference (glmark2
  terrain ~2.5 GHz / 38 W with and without it).

## Upstream and reporting

- [ ] File the NVIDIA bug drafted in `docs/nvidia-gb20b-suspend.md`: 620.73.04 marks GB20B as
  power-management-unsupported and patch 0010 restores working s2idle.
- [ ] Confirm whether DGX Spark's GB10 (10de:2e12) is a GB20B (`PMC_BOOT_42` as root on spark1).
  0010 now exempts only the N1x laptop IDs either way; the answer belongs in the NVIDIA report.
- [ ] Comment on NVIDIA/open-gpu-kernel-modules#1521 with our dock / charger / battery GPU clock
  table and the override result.
- [ ] Comment on seankd3/asus-proart-p16-rtx-spark-linux#10 with the `_PRW` finding, and the SSDT
  result if there is one.
- [ ] Open a PR to LeonMarzollDev/proart-p16-linux from `bsneed/install-lsp-plugins` (installs
  `lsp-plugins-lv2`, which PipeWire needs for the speaker crossover).
- [ ] Tell Leon how his DKMS modules fare on 7.3: proart-battery and proart-audio still needed;
  hid-asus-proart replaces the kernel's hid-asus but lacks Omarchy's 1104 (backlight off in sleep)
  and 1109 (Copilot key).

## Repo and CI

- [ ] Check the GitHub Actions arm64 `debs` job (runs 44958464353 on main, 44971485550 on
  `bsneed/review-fixes`). If it can't finish within
  Actions' limits, drop or rework it and update the README's CI paragraph.
- [x] Work through the code-review findings (2026-11-21, branch `bsneed/review-fixes`; every
  finding's resolution is in `docs/reviews/2026-11-21-initial-resolutions.md`).
- [ ] A plain `dpkg -i` / `apt install` of `nvidia-n1x-dkms-620-open` builds the modules only for
  the running and the newest kernel (DKMS's `common.postinst`); `install.sh` builds the rest.
  Decide whether the postinst should build for every kernel with headers itself.
- [ ] `install.sh` doesn't check the free space in `/boot` before installing the kernel (an
  initramfs per kernel); Ubuntu's own kernel packages don't either.

## rtx24 housekeeping

- [ ] Remove passwordless sudo (`/etc/sudoers.d/90-bsneed-nopasswd`) once bring-up is done.
- [ ] Decide on the touchpad (TP) firmware update MyASUS offers. Skipped for now: Leon's libinput
  quirk and haptics are tuned to the current firmware.
- [ ] *(optional)* proart-p16-linux's `optional/ui-control.sh` (ydotool) for remote GUI testing.
- [ ] *(optional)* Secure Boot with our own MOK key for the kernel and DKMS modules.
