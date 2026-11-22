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

**Status:** works on the ASUS ProArt P16 H7607BA (BIOS H7607BA.300) with Ubuntu 26.04, as a
second kernel next to Ubuntu's. Validated on 2026-11-21: USB4 docks (displays, USB 3, 10GbE),
s2idle, NVIDIA 620 and the proart-p16-linux setup. Its `tools/check.sh` gives 44 OK, 1 WARN,
0 FAIL, as on Ubuntu's kernel, except that some boots add a WARN for SoundWire probe-deferral
messages (`mtk_sdw_mc … -517`). See [Known issues](#known-issues). Everything was validated on
BIOS 300; recheck after a BIOS update.

## What's in it

| Piece | What it is |
|---|---|
| `linux-image-7.3.0-n1x1`, `linux-headers-7.3.0-n1x1` | kernel.org 7.3 + Omarchy's 579 kernel patches in the recipe's order + `patches/ubuntu/` (none so far), on Ubuntu's `linux-nvidia` 7.0.0-1026 config + `config/n1x.config`, built with the kernel's `make bindeb-pkg`. It installs next to Ubuntu's kernels. |
| `nvidia-n1x-dkms-620-open` | NVIDIA's open GPU kernel modules 620.73.04, built from the full source tree through DKMS, with Omarchy's seven N1x patches rebased onto 620 and one suspend fix (`patches/nvidia/`). It stands in for Ubuntu's `nvidia-dkms-620-open`, whose modules link NVIDIA's prebuilt `nv-kernel.o_binary` and `nv-modeset-kernel.o_binary`. Seven of the eight patches change that code, so they can't go in through Ubuntu's package. |
| NVIDIA user space | Ubuntu's `nvidia-*-620` packages, version `620.73.04-0ubuntu0.26.04.1`: the same set that proart-p16-linux's `install/02-nvidia.sh` installs for 615. |

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
`patches/nvidia/0010` restores 615's behaviour for GB20B. [docs/nvidia-gb20b-suspend.md](docs/nvidia-gb20b-suspend.md)
has the details, the evidence, a draft report for NVIDIA, and when to drop the patch.

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
- **`patches/ubuntu/`**: deltas this packaging needs on top of Omarchy. There are none so far.
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
| ASUS ProArt P16 H7607BA (RTX Spark N1X, 5120-core GPU, 10de:2e06) | H7607BA.300 | Tested, works |

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

On the laptop, with the packages in `out/` (copied there, or built there):

```sh
sudo bash scripts/install.sh
sudo reboot                      # boots 7.3.0-n1x1 once
bash scripts/check.sh            # kernel, USB4, NVIDIA
sudo bash scripts/install.sh --default   # after a good boot: make it GRUB's default
```

Secure Boot must be off: the kernel is signed with a throwaway build key, which shim and the
firmware don't trust, so `install.sh` stops if `mokutil --sb-state` reports it on.

`install.sh` first checks everything it can without changing anything: the packages in `out/`
against `SHA256SUMS` (a package rebuilt under a version that is already installed is refused;
raise the revision in `sources`), `/etc/default/grub`, and the whole apt transaction, which it
simulates (`apt-get -s`). It stops if apt can't do it, would remove anything it didn't ask for,
or would install a NVIDIA 620 package of another version than 620.73.04. Then it:

1. Installs the kernel and headers packages.
2. Installs NVIDIA 620: Ubuntu's user space, taken from `resolute-proposed` while 620 is only
   there (that source is temporary, pinned to priority 1 and removed when the script ends),
   and `nvidia-n1x-dkms-620-open`. It removes the packages of other NVIDIA driver versions
   (a 615 or 580 in the name: e.g. `nvidia-utils-615`, `nvidia-firmware-615-*` and the
   prebuilt `linux-modules-nvidia-615-open-*`) and Ubuntu's `nvidia-dkms-620-open`, and
   nothing else: `nvidia-settings`, `nvidia-prime`, `nvidia-container-toolkit`,
   `libnvidia-container1` and other packages of no particular driver version stay. It builds
   the DKMS modules for every kernel with headers, Ubuntu's `linux-nvidia` included, so the
   fallback kernel keeps a GPU driver; if that build fails for any kernel that boots, it stops
   with an error before touching GRUB. It then refreshes every initramfs, since the kernel
   loads the NVIDIA modules from there.
3. Writes `/etc/apt/preferences.d/n1x-kernel-ubuntu-nvidia`, which holds the NVIDIA user space
   at the module version: 620.73.04, any Ubuntu revision of it (see [Updates](#updates)).
4. Adds `pci=hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=32G` to
   `GRUB_CMDLINE_LINUX_DEFAULT`. Docks need this PCI hotplug padding behind the USB4 tunnel
   root ports; the values are Omarchy's for the ProArt P14/P16. Running it again changes
   nothing. An existing `pci=` keeps its other options. It stops before changing anything if
   `/etc/default/grub` sets the variable in a form it can't edit (indented, `export`), or if a
   file in `/etc/default/grub.d/` replaces it; after `update-grub` it checks that `grub.cfg`
   boots the new kernel with these options.
5. Keeps the running kernel as GRUB's default and boots the new one once (`grub-reboot`). A
   hang or SoC reset on that boot falls back to the old kernel on the next one. That needs
   `GRUB_DEFAULT=saved` (proart-p16-linux sets it; stock Ubuntu has `0`, which boots the
   newest kernel whatever `grub-set-default` says), so `install.sh` sets it and `--remove`
   puts the old value back. After `--default`, running `install.sh` again keeps the new kernel
   as the default.

It records what it replaced in `/var/lib/n1x-kernel-ubuntu`.

### Kernel command line

- `acpi_osi="!Windows 2022"` (from proart-p16-linux) stays. Ubuntu's `linux-nvidia` kernel
  needs it to see the SSPM, and GRUB's command line is shared by every kernel. On this kernel
  it overrides Omarchy's `_OSI` quirk (1106), which exposes the SSPM the same way.
- No `mem_sleep_default=s2idle`: 1113 makes s2idle the default.
- No `power_wrap_drv.usb4_release=0`: 1112 makes that the default on N1x laptops.

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

- In s2idle only the internal keyboard and the power button wake the P16. None of these do:
  RTC alarms (rtc0; rtc1 returns EIO), Wake-on-LAN through the dock, USB devices on the dock,
  and Wi-Fi WoWLAN. The likely cause is BIOS 300's ACPI tables: the PCIe root ports (`RP0`)
  have `_S0W` 0x04 but no `_PRW`, so nothing behind them can signal a wake
  (seankd3/asus-proart-p16-rtx-spark-linux#10).
- NVIDIA 620's user space is in `resolute-proposed` only (Nov 2026). The apt pin holds it at
  the module version.
- The kernel is kernel.org 7.3, as Omarchy's recipe pins it, without the 7.3.x stable fixes.
- `thunderbolt-platform NVDA8100: RX overflow for ring 0` appears in the kernel log when a dock
  connects. Nothing has failed because of it.
- Ubuntu's kernel SAUCE (AppArmor's Ubuntu-only extensions among them) is not in this kernel.
  AppArmor loads the snap profiles, and proart-p16-linux's snap EGL check passes; snap
  confinement was not tested further.
- proart-p16-linux's kernel-error check sometimes WARNs on SoundWire probe deferral
  (`mtk_sdw_mc: failed to parse sdw devices/endpoints: -517`), which the kernel retries. Audio
  works.
- nvidia-powerd isn't in Ubuntu's arm64 620 packages. NVIDIA's aarch64 `.run` has it
  (version 2.0), but it exits at once on the P16 without reporting NVPCF.

## Remove

```sh
sudo bash scripts/install.sh --remove
sudo reboot
```

This reinstalls the NVIDIA packages that were there before (by name, at the version the
archive has now, e.g. Ubuntu's 615 and its prebuilt modules for `linux-nvidia`: the exact
versions from back then may be gone after a security update), purges
`nvidia-n1x-dkms-620-open`, the 620 user space and every `linux-image/headers-*-n1x*`
package, removes the apt pin and our `pci=` options, and points GRUB's default back at the kernel that was running at install time
(Ubuntu's `linux-nvidia`). The kernel command line and `GRUB_DEFAULT` go back to what they
were before the first install (a `pci=` value of yours that the install replaced comes back;
an option you had already stays); a later edit of your own to either is kept. It simulates
both apt transactions first and keeps the apt pin until the NVIDIA packages are back, so a
failure leaves a consistent 620 install that `--remove` can be run on again.

## Updates

- **Ubuntu kernels**: unaffected. A new `linux-nvidia` kernel gets our NVIDIA modules from
  DKMS when its headers are installed, as it would with Ubuntu's DKMS package.
- **NVIDIA user space**: the apt pin holds the upstream version 620.73.04 and takes any Ubuntu
  revision of it, so it follows the move from `-proposed` to `-updates` and Ubuntu's respins
  of 620.73.04 (security fixes Ubuntu backports into this version included). It also holds
  back every newer NVIDIA release, security releases included: those wait until this
  repository moves to them, since the modules must be built from the same version. Moving to
  a newer driver means changing `NVIDIA_VERSION` in `sources`, re-checking `patches/nvidia`,
  rebuilding and running `install.sh` again. Watch NVIDIA's security bulletins while you run
  this. A change to `patches/nvidia` alone raises `NVIDIA_N1X_REVISION`, so dpkg sees a new
  version. The package refreshes every initramfs when it installs, because the kernel loads
  the NVIDIA modules from there.
- **This kernel**: a new Omarchy pin or kernel.org version is a change to `sources`, with
  `N1X_REVISION` raised. Each revision is a new package name (`linux-image-7.3.0-n1x2`), so it
  installs next to the previous one, as Ubuntu's kernels do.

## Tests

```sh
bash tests/run.sh                # version parsing, cmdline edits, GRUB entries, config check
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
