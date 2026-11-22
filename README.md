# n1x-kernel-ubuntu

Omarchy's NVIDIA N1x kernel (`linux-omarchy-aarch64` 7.3) and NVIDIA 620 with Omarchy's N1x
display fixes, packaged as Ubuntu 26.04 arm64 `.deb`s. It gives N1x laptops on Ubuntu working
USB4/Thunderbolt docks (displays, USB 3, Ethernet) and the rest of Omarchy's N1x work: s2idle
that actually sleeps, keyboard wake, SSPM and power_wrap fixes, audio and UCSI fixes.

Ubuntu's own N1x kernel (`linux-nvidia` 7.0) has no driver for the N1x USB4 host routers, so a
Thunderbolt dock falls back to USB 2.0 with no DisplayPort. Omarchy's recipe has that driver
and everything it needs. This repository builds that recipe, unchanged, for Ubuntu, and keeps
Ubuntu's user space: Ubuntu's kernel config, Ubuntu's NVIDIA packages, and the userspace setup
of [proart-p16-linux](https://github.com/LeonMarzollDev/proart-p16-linux).

**Status:** works on one machine, an ASUS ProArt P16 H7607BA (18-core RTX Spark N1X, GPU
10de:2e06, BIOS H7607BA.300) with Ubuntu 26.04 and proart-p16-linux, as a second kernel next to
Ubuntu's. Validated on 2026-11-21 with a CalDigit TS5 Plus dock and a Dell U4025QW monitor:
USB4 (DisplayPort, USB 3, 10GbE), s2idle, NVIDIA 620 and the proart-p16-linux setup. Its
`tools/check.sh` gives 44 OK, 1 WARN, 0 FAIL, as on Ubuntu's kernel, except that some boots add
a WARN for SoundWire probe-deferral messages (`mtk_sdw_mc … -517`). Not everything works yet:
the dock's monitor runs at 60 Hz at most, and replugging a dock loses its display (see
[Known issues](#known-issues)); see [Supported hardware](#supported-hardware) for what was not
tested. Everything was validated on BIOS 300; recheck after a BIOS update.

## What's in it

| Piece | What it is |
|---|---|
| `linux-image-7.3.0-n1x1`, `linux-headers-7.3.0-n1x1` | kernel.org 7.3 + Omarchy's 579 kernel patches in the recipe's order + `patches/ubuntu/` (one 7.3.2 stable fix), on Ubuntu's `linux-nvidia` 7.0.0-1026 config + `config/n1x.config`, built with the kernel's `make bindeb-pkg`. It installs next to Ubuntu's kernels. |
| `nvidia-n1x-dkms-620-open` | NVIDIA's open GPU kernel modules 620.73.04, built from the full source tree through DKMS, with Omarchy's seven N1x patches rebased onto 620 and one suspend fix (`patches/nvidia/`). It stands in for Ubuntu's `nvidia-dkms-620-open`, whose modules link NVIDIA's prebuilt `nv-kernel.o_binary` and `nv-modeset-kernel.o_binary`. Seven of the eight patches change that code, so they can't go in through Ubuntu's package. |
| NVIDIA user space | Ubuntu's `nvidia-*-620` packages, 620.73.04 (validated with `620.73.04-0ubuntu0.26.04.1`, from `resolute-proposed`): the same set that proart-p16-linux's `install/02-nvidia.sh` installs for 615. |

Every input is pinned in [`sources`](sources) (kernel tarball and NVIDIA source SHA-256,
omarchy-pkgs commit, the Ubuntu package the base config comes from) and is checked before use.

### Why NVIDIA 620

620.73.04 is the first release whose README lists the N1x device IDs (2E03, 2E06, 2E13), and
it passes NVPCF 3.x (`_DSM` revision 0x300) through to user space. Ubuntu has its user space
for 26.04 arm64 in `resolute-proposed` (Nov 2026). The NVIDIA user space and kernel modules
must be the same version. `scripts/install.sh` pins the user space to that version, so
`apt upgrade` can't move it away from the modules. See [Updates](#updates).

620 alone refuses system suspend on the N1x: it lists the N1x GPU (GB20B) as not supporting
power management, so every s2idle attempt fails with `NVRM: PM suspend notifier failed: 0x56`.
`patches/nvidia/0010` restores 615's behaviour for the three N1x laptop GPUs only (PCI device
IDs 2E03, 2E06, 2E13). Every other GPU on 620's list keeps 620's behaviour, including DGX
Spark's GB10 (2E12), which seems to be a GB20B too and may be what NVIDIA meant the entry for.
[docs/nvidia-gb20b-suspend.md](docs/nvidia-gb20b-suspend.md) has the details, the evidence, a
draft report for NVIDIA, and when to drop the patch. `install.sh` refuses to run on a machine
without one of those three GPUs.

615 (what Omarchy ships) isn't used here. Ubuntu's 615 user space is 615.71.09, whose kernel
modules don't build on 7.3 (the `dmem_cgroup` API changed). 615.78.08, which does, has no
Ubuntu user space.

### Patches

- **Omarchy kernel patches** (`OMARCHY_COMMIT` in `sources`, `pkgbuilds/linux-omarchy-aarch64`
  at pkgrel 75). These are all of the recipe's `*.patch` sources except the `nvidia-*` ones,
  applied in its `source=()` order with `patch -Np1 --fuzz=0`, as its `prepare()` does (plus
  `--batch`, so a patch never stops for a question). The build reads the order from the pinned
  PKGBUILD itself. Omarchy's
  [README](https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/linux-omarchy-aarch64/README.md)
  explains each patch. The N1x USB4 work is 1070–1089, 1105 and 1112; the ProArt P16 gets
  1012, 1106, 1107 and 1108.
- **`patches/ubuntu/`**: deltas this packaging needs on top of Omarchy, applied after its
  patches the same way. 0001 is the 7.3.2 stable fix for an MT7925 Wi-Fi reset panic that hangs
  the P16 (upstream c182bfe944eb, CVE-2026-99560); it goes once the base is 7.3.2 or newer.
  Ubuntu-specific needs are config-only (`config/n1x.config`).
- **`patches/nvidia/`**: Omarchy's `nvidia-open-dkms` 0003–0009 (written for 615.78.08),
  rebased onto 620.73.04. None of them are in 620. 0003, 0004, 0006 and 0008 apply as they
  are. 0005, 0007 and 0009 needed context-only changes, which a note in each patch describes.
  0010 is this repository's: it lets the N1x GPU go through system suspend on 620 (see
  [Why NVIDIA 620](#why-nvidia-620)). They are applied with `--forward --fuzz=0`, so a patch
  that a new NVIDIA release already contains fails the build instead of being reverted
  (Omarchy's `prepare()` uses `--batch` alone, which assumes such a patch is reversed and
  undoes it).
- **`nvidia-dkms/patches/`**: Ubuntu's own buildfix for its 7.0 kernels, applied by DKMS for
  `7.0.0-*` kernels only, as Ubuntu's package does. It lets the same DKMS module build for the
  `linux-nvidia` fallback kernel.

### Config

The base is Ubuntu's `/boot/config-7.0.0-1026-nvidia`, taken from the
`linux-headers-7.0.0-1026-nvidia` 7.0.0-1026.27 package and checked by SHA-256. That is
NVIDIA's own N1x config, so AppArmor, the LSM order, BTF, Rust, squashfs for snaps and the
rest of what Ubuntu's user space expects stay as Ubuntu has them. `config/n1x.config` holds
what differs, with a reason for each line: the options Omarchy's patches add
(`USB4_PLATFORM_NHI`), Ubuntu's signing-key paths cleared, and the platform options the N1x
depends on. The build fails if any line does not survive `olddefconfig`
(`scripts/config-check.sh`).

## Supported hardware

| Machine | BIOS | Result |
|---|---|---|
| ASUS ProArt P16 H7607BA: RTX Spark N1X with the 18-core CPU and the 5120-core GPU (10de:2e06) | H7607BA.300 | Tested, works, with the known issues below |

Tested on it: the internal OLED panel (eDP), the keyboard, touchpad, speakers, headphones and
microphone (through proart-p16-linux), s2idle with keyboard wake, NVIDIA 620 (`nvidia-smi`,
glmark2), and over USB4 a CalDigit TS5 Plus dock (USB 3, 10GbE) with a Dell U4025QW monitor
(DisplayPort, its USB hub and 2.5GbE) behind it.

Not tested on 7.3: the HDMI output, the internal camera, a monitor plugged straight into a USB-C
port, two monitors at once, eGPUs and other USB4/Thunderbolt devices than these two, and the
6144-core N1X (10de:2e03, 2e13). `install.sh` refuses to run without one of the three N1X GPUs.

Other N1x laptops that Omarchy's recipe supports (ProArt P14, Zenbook A14/A16, Dell, Lenovo,
Surface) should work with the same packages. They are untested here. The `pci=` values in
`install.sh` are Omarchy's for the ProArt P14/P16.

### With proart-p16-linux

Install [proart-p16-linux](https://github.com/LeonMarzollDev/proart-p16-linux) as usual. Its
three DKMS modules build for this kernel, and its apt hook builds them for new kernels:

- `proart-battery` is still needed. The ACPI battery reports zeros, and this kernel carries no
  ASUS WMI battery driver.
- `proart-audio` is still needed and doesn't conflict. Omarchy's 1060 gives the sound card its
  ACPI subsystem ID, and `proart_audio` gives the CS35L56 amplifiers their tuning (firmware UID
  10431484).
- `hid-asus-proart` replaces this kernel's `hid-asus` (DKMS modules in `updates/` take
  precedence), so only one driver binds the keyboard. Leon's driver has the Fn-lock attribute,
  backlight cycling and the media-key default (via `fnlock_default=0`) that his user space uses.
  It does not have Omarchy's 1104 (keyboard backlight off during sleep) or 1109 (Copilot key as
  F23).

## Build

On Ubuntu 26.04 arm64:

```sh
sudo apt-get install $(cat scripts/build-deps.txt)
bash scripts/build.sh            # out/*.deb, out/SHA256SUMS
```

Or on any arm64 machine with Docker, in a clean `ubuntu:26.04` container:

```sh
bash scripts/container-build.sh
```

`build/` holds the downloads and the kernel tree (about 35 GB). Delete it when you're done.
The build also builds the NVIDIA modules once against the new kernel tree, so a kernel API
break fails the build rather than the install. `--skip-nvidia-test` skips that step.

From a clean checkout, `scripts/container-build.sh` takes about 18 minutes on a 20-core arm64
machine (NVIDIA DGX Spark). That covers downloads, the container's build dependencies, the
kernel, and the NVIDIA DKMS package with its test build.

The `debs` job in `.github/workflows/build.yml` runs the same build on GitHub's
`ubuntu-24.04-arm` runner in an `ubuntu:26.04` container. It runs on tags, by hand
(`workflow_dispatch`), or for a commit whose message contains `[build]`, and uploads `out/`.

## Install

### Before you start

On the ProArt P16 the supported and tested order is:

1. Ubuntu 26.04 with [proart-p16-linux](https://github.com/LeonMarzollDev/proart-p16-linux) run
   completely (`install/01`–`11`, then `user/install-user.sh`), and its `tools/check.sh` clean.
   (The P16 here ran 01–07, 09 and 11; 08, the camera, and 10, power, were skipped.)
2. Then build and install n1x-kernel-ubuntu, as below.

That order matters. The fallback kernel and `--remove` go back to what proart-p16-linux's 01
and 02 install, Ubuntu's `linux-nvidia` with NVIDIA 615. The battery and speaker tuning come from
its DKMS modules, and `acpi_osi` on the command line comes from its 01. `install.sh` warns when
the kernel it falls back to isn't a `linux-nvidia` one.

proart-p16-linux is for the P16 only. On another N1x laptop, set up a working Ubuntu
`linux-nvidia` kernel with Ubuntu's NVIDIA driver first. That route is untested.

### Install

On the laptop, with the packages in `out/` (copied there, or built there):

```sh
sudo bash scripts/install.sh
sudo reboot                      # boots 7.3.0-n1x1 once
bash scripts/check.sh            # kernel, USB4, NVIDIA
sudo bash scripts/install.sh --default   # after a good boot: make it GRUB's default
```

Secure Boot must be off (the kernel is signed with a throwaway key). `install.sh` checks
everything it can, the whole apt transaction included, before it changes anything. It replaces
only the packages of other NVIDIA driver versions, builds the NVIDIA modules for every kernel,
pins the NVIDIA user space to 620.73.04, adds the USB4 `pci=` options, and boots the new
kernel once. [docs/install.md](docs/install.md) has each step, the kernel command line, what
`--remove` undoes and how updates work.

### Docks

Tested on the ProArt P16 with:

- **CalDigit TS5 Plus**: USB4 at 40 Gb/s (2 × 20), authorized by Bolt automatically
  (`iommu_dma_protection=1`, no `boltctl enroll`). Its USB hubs run at 10000M, and its 10GbE
  (AQC113, `atlantic`, a PCIe tunnel) links at 10000 Mb/s.
- **Dell U4025QW** (USB4 monitor, behind the TS5 Plus): a DisplayPort tunnel with 36 modes,
  and its 2.5GbE (RTL8156B, `r8152`) at USB 5000M.

Docks and displays come back after s2idle. Ubuntu's own kernel sees the same dock as USB 2.0
Billboard devices.

## Known issues

- A monitor behind the dock runs at 60 Hz at most: the Dell U4025QW through the CalDigit TS5
  Plus offers 60 Hz on 7.3 + NVIDIA 620, where the same monitor, dock and cable run 5120x2160 at
  120 Hz on a Mac. The cause is still open (DSC through the tunnel, the tunnel's bandwidth
  allocation, or the mode list); see [TODO.md](TODO.md).
- Dock display hotplug is broken. Unplugging the dock doesn't move the desktop back to the
  internal panel until the lid is closed and opened. Moving the dock to another USB-C port gave
  no picture, plus a kernel WARN in `nvidia_drm` (`__nv_drm_handle_flip_event`). The dock's USB
  and Ethernet come back fine; only DisplayPort doesn't. Once, minutes after a replug, the PCIe
  hotplug path (`irq/…-pciehp`) held a lock long enough to stall NetworkManager and tailscaled
  for two minutes. Plug the dock in before logging in, and keep it on one port. Details are in
  [TODO.md](TODO.md).
- In s2idle only the internal keyboard and the power button wake the P16. None of these do:
  RTC alarms (rtc0; rtc1 returns EIO), Wake-on-LAN through the dock, USB devices on the dock,
  and Wi-Fi WoWLAN. The likely cause is BIOS 300's ACPI tables: the PCIe root ports (`RP0`)
  have `_S0W` 0x04 but no `_PRW`, so nothing behind them can signal a wake
  (seankd3/asus-proart-p16-rtx-spark-linux#10).
- NVIDIA 620's user space is in `resolute-proposed` only (Nov 2026), so a fresh install needs
  620.73.04 to still be published there or in `-updates`. Any Ubuntu revision of 620.73.04 will
  do. Once Ubuntu moves 620 on to a newer upstream version and drops 620.73.04, `install.sh`
  stops before changing anything, and this repository has to move to that version. The apt pin
  holds the installed user space at the module version.
- The kernel is kernel.org 7.3, as Omarchy's recipe pins it, without the 7.3.x stable fixes
  except the MT7925 reset fix in `patches/ubuntu/`.
- `thunderbolt-platform NVDA8100: RX overflow for ring 0` appears in the kernel log when a dock
  connects. Nothing has failed because of it.
- Ubuntu's kernel SAUCE, AppArmor's Ubuntu-only extensions among them, is not in this kernel.
  AppArmor is enabled and loads the snap profiles, and proart-p16-linux's snap EGL check passes.
  Two differences from stock Ubuntu: `kernel.apparmor_restrict_unprivileged_userns` doesn't exist,
  so unprivileged user namespaces aren't restricted as Ubuntu restricts them, and the snap
  `prompting-client` service fails. Snap confinement was not tested further.
- proart-p16-linux's kernel-error check sometimes WARNs on SoundWire probe deferral
  (`mtk_sdw_mc: failed to parse sdw devices/endpoints: -517`), which the kernel retries. Audio
  works.
- nvidia-powerd isn't in Ubuntu's arm64 620 packages. NVIDIA's aarch64 `.run` has it
  (version 2.0), but it exits at once on the P16 without reporting NVPCF.

## FAQ

- **Red "Dependency failed for sssd-…socket" lines at boot?** Those are stock Ubuntu 26.04,
  not this kernel: sssd's sockets are enabled with no `/etc/sssd/sssd.conf`. If you don't use
  sssd, silence them with
  `sudo systemctl disable sssd-{nss,autofs,pac,pam,ssh,sudo}.socket`. `install.sh` doesn't do
  that for you.
- **An orange "Found ordering cycle" line at boot?** That one is Ubuntu's nvidia-persistenced
  unit, and `install.sh` takes care of it ([step 6](docs/install.md#what-installsh-does)).
  Run `install.sh` again after an NVIDIA update.

## Remove

```sh
sudo bash scripts/install.sh --remove
sudo reboot
```

This puts back the NVIDIA packages, GRUB settings and kernel command line from before the
install, and purges the N1x kernel packages ([details](docs/install.md#what---remove-does)).

## Updates

Ubuntu kernels get our NVIDIA modules through DKMS. The NVIDIA user space stays at 620.73.04,
so newer NVIDIA releases, security releases among them, wait until this repository moves to
them ([details](docs/install.md#updates)).

## Tests

```sh
bash tests/run.sh                # the helpers in scripts/: tests/t-*.sh
shellcheck scripts/*.sh tests/*.sh nvidia-dkms/postinst nvidia-dkms/prerm nvidia-dkms/postrm
```

## Credits

- [Omarchy](https://github.com/omacom/omarchy-pkgs): the `linux-omarchy-aarch64` recipe and
  its N1x patches (Birk Skyum and the Omarchy authors), and the NVIDIA N1x display patches
  (`nvidia-open-dkms`).
  This repository only packages their work for Ubuntu.
- NVIDIA's [NV-Kernels](https://github.com/NVIDIA/NV-Kernels) N1x SAUCE, which Omarchy's
  1000–1040 and 1090–1096 carry, and NVIDIA's
  [open GPU kernel modules](https://github.com/NVIDIA/open-gpu-kernel-modules).
- The ProArt P16 work this builds on:
  [LeonMarzollDev/proart-p16-linux](https://github.com/LeonMarzollDev/proart-p16-linux) (the
  Ubuntu userspace this kernel is meant for),
  [johannhartmann/asus-proart-p16-rtx-spark-linux](https://github.com/johannhartmann/asus-proart-p16-rtx-spark-linux)
  and [seankd3/asus-proart-p16-rtx-spark-linux](https://github.com/seankd3/asus-proart-p16-rtx-spark-linux).
- Ubuntu's kernel and NVIDIA packaging (the base config and the 7.0 DKMS buildfix).

## License

GPL-2.0-only, as the kernel. The NVIDIA open kernel modules are dual MIT/GPL-2.0 (their
`COPYING` ships in the DKMS package).
