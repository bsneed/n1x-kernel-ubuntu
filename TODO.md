# TODO

Open work on n1x-kernel-ubuntu and the ASUS ProArt P16 (H7607BA, BIOS H7607BA.300) it was
validated on. Check items off here when they land; move anything that turns into a known
limitation into the README.

## Display

- [x] **Dell U4025QW at 5120x2160 120 Hz** (2026-11-22). Use the laptop's **HDMI** port. It runs
  `HDMI FRL (DSC)` at 120 Hz with VRR, and survives reboots, unplugs and replugs. Put the keyboard
  and mouse on the TS5 Plus, which then carries only USB and Ethernet. Through a USB4
  DisplayPort tunnel (the TS5 Plus's DP port, or the Dell's own Thunderbolt input) the link is
  unreliable:
  - The first tunnel after a boot or a full reconnect trains at HBR x4 (8640 Mb/s), where DSC
    fits only 60 Hz. Replugging the DP cable, or power-cycling the Dell, rebuilds the tunnel at
    HBR3 x4 (25920 Mb/s), and 120 Hz is offered. Seen on the dock's DP OUT (1:11) with the Dell's
    hub out of the path, so it isn't the Dell's Thunderbolt Daisy Chain setting or its inputs.
  - Best guess, not proven: the N1x DP IN's hardware DPCD auto-read (NVIDIA Bug 6102109) records
    the lower rate, and NVIDIA's software auto-read workaround (Realtek sinks; the Dell reports
    OUI 00:E0:4C) is applied only after that first read. Logs: rtx24 `/home/bsneed/work/testA/`.
  - Not reported to NVIDIA; the data isn't conclusive enough.
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
- [x] Report the nvidia-persistenced ordering cycle against Ubuntu's nvidia-graphics-drivers-620
  (2026-11-21, [LP #2175497](https://bugs.launchpad.net/bugs/2175497)). Drop the override from
  `install.sh` once a fixed `nvidia-compute-utils-620` is published.
- [x] **README: AppArmor differs from stock Ubuntu** (2026-11-21, Known issues).
- [ ] *(moot with HDMI)* **Dock hotplug with a display on the USB4 tunnel.** Seen 2026-11-21/22 on
  7.3 + NVIDIA 620, only when the Dell is carried over the tunnel:
  - On a cable unplug, `nvidia-modeset` logs `AuxChCtl Failing` and `DPCONN> Zombie? 1` and keeps
    the connector alive, so GNOME doesn't fall back to the internal panel (or does so late).
    Turning the Dell off (DP adapter unplug, USB4 link stays up) falls back instantly.
  - On a replug, GNOME's modeset waits about 30 s for the dock's PCIe tunnel
    (`pciehp: Slot(0): Card present / Link Up`); PipeWire underruns (audio blips) at that moment.
  - The port next to HDMI brought no picture once, with a WARN in `nvidia_drm`
    (`__nv_drm_handle_flip_event`); dmesg in rtx24 `/home/bsneed/work/replug-1628/`.
  - Once, ~6 min after a replug, NetworkManager, tailscaled and kernel workers hung >2 min on a
    mutex held by `irq/315-pciehp`. Worth watching for with the dock carrying only USB/Ethernet.

## Kernel

- [ ] **Move the base to 7.3.2 or newer and drop `patches/ubuntu/0001`** (the MT7925 reset-panic
  fix, upstream c182bfe944eb, in 7.3.2). Omarchy's recipe pins kernel.org 7.3; either wait for
  it to move, or take the 7.3.x tarball ourselves (build.sh checks that the recipe's tarball is
  `sources`' one, so that is a build.sh change). With 0001 still there, the build fails on it as
  already applied, which is the reminder.

## Power and suspend

- [ ] **Unattended wake from s2idle.** Only the internal keyboard and the power button wake the
  P16. RTC alarms (rtc0; rtc1 returns EIO), Wake-on-LAN through the dock, USB devices on the dock
  and Wi-Fi WoWLAN do not. BIOS 300's DSDT gives the PCIe root ports (`RP0`) `_S0W 0x04` but no
  `_PRW` (see seankd3/asus-proart-p16-rtx-spark-linux#10). Try an SSDT override from the initramfs
  that adds `_PRW`, then retest Wi-Fi and dock wake.
- [ ] **Closing the lid doesn't suspend.** ACPI `LID0` (PNP0C0D) always reads "open": its `_LID`
  returns `EC0.GLID()`, an EC call over FF-A, and no lid event has ever reached logind on rtx24.
  With the lid closed, the EC flashes the front white LED (its sleep indicator) while Linux stays
  awake. Workaround: suspend from the menu or the power button first. Next: query `GLID` with
  proart-p16-linux's `tools/ffa-probe.sh` lid open vs closed, to see whether the EC answers
  wrongly or Linux reads it wrongly. Possibly the same EC event gap as the missing `_PRW` above.
- [ ] **Touchpad firmware V1.26.0918.1** (installed by Windows 2026-11-22). The first Linux
  boots afterwards had no internal keyboard or touchpad (`i2c_hid_acpi ... failed to fetch HID
  descriptor: -110` on MKB0001 and the touchpad; the Asus keyboard handshake returned zeros).
  A boot through Windows, then a cold boot, cleared it. If it comes back: try
  `modprobe -r i2c_hid_acpi; modprobe i2c_hid_acpi`, and check whether Leon's libinput quirk and
  haptics still fit the new firmware.
- [ ] **BIOS update** once ASUS publishes something newer than H7607BA.300 for this model (none
  as of 2026-11-21). The BIOS-300 baseline (ACPI dump and both `check.sh` outputs) is in
  `/home/bsneed/work/bios-300-baseline/` on rtx24 and spark1. Diff the new tables for `_PRW`, then
  rerun the regression and wake tests.
- [ ] **Long-sleep audio test.** Suspend for 30+ minutes and check the mic, headphone jack and
  tweeters. If they die, try proart-p16-linux's `optional/sleep-audio.sh`.
- [ ] **Re-verify s2idle with patch 0010 revision 2** (`NVIDIA_N1X_REVISION=2`, scoped to
  10de:2e03/2e06/2e13): a real suspend/resume on rtx24 with the dock, as for revision 1. A
  `pm_test=devices` s2idle cycle passed on 2026-11-21 (the PM notifier no longer refuses).
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
- [ ] Follow Ubuntu's [LP #2175498](https://bugs.launchpad.net/bugs/2175498)
  (gnome-shell-ubuntu-extensions, filed 2026-11-21): the Show Apps grid is empty after
  50.26.04.8ubuntu. Plain Ubuntu, not ours.
- [ ] Tell Leon how his DKMS modules fare on 7.3: proart-battery and proart-audio still needed;
  hid-asus-proart replaces the kernel's hid-asus but lacks Omarchy's 1104 (backlight off in sleep)
  and 1109 (Copilot key).

## Repo and CI

- [ ] Check the GitHub Actions arm64 `debs` job (runs 44958464353 on main, 44971485550 on
  `bsneed/review-fixes`). If it can't finish within
  Actions' limits, drop or rework it and update the README's CI paragraph.
- [x] Work through the code-review findings (2026-11-21, branch `bsneed/review-fixes`; every
  finding's resolution is in `docs/reviews/2026-11-21-initial-resolutions.md`, and those of the
  exit-gate review in `docs/reviews/2026-11-21-exit-gate-resolutions.md`).
- [x] ~~Make the postinst build for every kernel with headers.~~ Not needed on 26.04: its dkms
  (3.2.2-1ubuntu1) ships `autoinstall_all_kernels="yes"`, so DKMS's `common.postinst` already
  builds for every kernel with headers. `install.sh`'s `dkms_all_kernels` stays as the check
  that fails loudly.
- [ ] The DKMS package records the commit it was built from (`SOURCE`), so every rebuild from
  a new commit needs `NVIDIA_N1X_REVISION` raised, even when the modules are unchanged (it went
  to 3 for kernel revision 2 alone). Decide whether the commit belongs in that package.
- [ ] `install.sh` doesn't check the free space in `/boot` before installing the kernel (an
  initramfs per kernel); Ubuntu's own kernel packages don't either.
- [ ] *(optional)* `--remove` removes `nvidia-n1x-dkms-620-open` and the 620 user space
  (`name-`), so dpkg keeps their `rc` records (the container rehearsal of the exit-gate fixes).
  docs/install.md now says "removes". Our package has no conffiles, so purging it (`name_`)
  would only drop that record; for the 620 user space, check first that a purge in the same
  transaction as 615's install can't delete a conffile 615 now owns.
- [ ] `--remove` puts Ubuntu's `nvidia-dkms-620-open` back while 7.3 is still installed, so DKMS
  builds Ubuntu's modules for 7.3 too; purging 7.3 afterwards leaves `/lib/modules/7.3.0-n1x1`
  with them and a `dkms status` entry (seen in the exit-gate container rehearsal; `dkms
  kernel_prerm` removed nothing). Check on hardware, and consider purging the kernel packages
  before the NVIDIA restore, or `dkms remove` for the purged release.

## rtx24 housekeeping

- [ ] Remove passwordless sudo (`/etc/sudoers.d/90-bsneed-nopasswd`) once bring-up is done.
- [ ] Decide on the touchpad (TP) firmware update MyASUS offers. Skipped for now: Leon's libinput
  quirk and haptics are tuned to the current firmware.
- [ ] *(optional)* proart-p16-linux's `optional/ui-control.sh` (ydotool) for remote GUI testing.
- [ ] *(optional)* Secure Boot with our own MOK key for the kernel and DKMS modules.
