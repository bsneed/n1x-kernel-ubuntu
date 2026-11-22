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
- [ ] **Red and orange messages scroll past at boot.** Go through every error and warning, decide
  which are real, and fix or quiet the harmless ones. Seen in the journal so far:
  - ACPI errors from the EC lid method (`\_SB.EC0.RWEC` -> `GLID` -> `LID0._LID`, `AE_ERROR`),
    repeated during boot.
  - `GICv3: [Firmware Bug]: Illegal GSI2 translation request`.
  - About 15x `mtk_sdw_mc: failed to parse sdw devices/endpoints: -517` (probe deferral; audio
    works).
  - A PCI BAR message.
  - On the stock 7.0 kernel only: systemd timing out on `/dev/tpm0` (about 1.5 min of boot) and
    `nouveau: unknown chipset`.

  `quiet` still prints error-level messages and `console=tty0` sends them to the screen.

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
- [ ] *(optional)* **615 without `RMSkipACPIBattCap` on AC**, for a definitive answer on
  NVIDIA/open-gpu-kernel-modules#1521. On 7.3 + 620 the override made no difference (glmark2
  terrain ~2.5 GHz / 38 W with and without it).

## Upstream and reporting

- [ ] File the NVIDIA bug drafted in `docs/nvidia-gb20b-suspend.md`: 620.73.04 marks GB20B as
  power-management-unsupported and patch 0010 restores working s2idle.
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

- [ ] Check the GitHub Actions arm64 `debs` job (run 44958464353). If it can't finish within
  Actions' limits, drop or rework it and update the README's CI paragraph.
- [ ] Work through the code-review findings (`docs/reviews/`).

## rtx24 housekeeping

- [ ] Remove passwordless sudo (`/etc/sudoers.d/90-bsneed-nopasswd`) once bring-up is done.
- [ ] Decide on the touchpad (TP) firmware update MyASUS offers. Skipped for now: Leon's libinput
  quirk and haptics are tuned to the current firmware.
- [ ] *(optional)* proart-p16-linux's `optional/ui-control.sh` (ydotool) for remote GUI testing.
- [ ] *(optional)* Secure Boot with our own MOK key for the kernel and DKMS modules.
