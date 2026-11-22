# Installing, removing and updating

What `scripts/install.sh` does, what `--remove` undoes, and how updates work. The
[README](../README.md) has the short version and the commands.

## What install.sh does

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
   as the default. Once Ubuntu removes that old kernel (`apt autoremove` keeps the running and
   the two newest), `install.sh` and `--remove` say so and use the newest installed
   `linux-nvidia` kernel in its place; run `install.sh` again then, so GRUB's fallback follows.
6. Writes `/etc/systemd/system/nvidia-persistenced.service` when Ubuntu's unit needs it.
   `nvidia-compute-utils-620`'s unit says `Before=systemd-backlight@backlight:nvidia_0.service`
   but runs after `sysinit.target`, which that backlight unit runs before: on the N1x, whose
   panel backlight is the NVIDIA GPU's, systemd reports `Found ordering cycle` at every boot
   and drops a job to break it. A drop-in can't take an entry out of `Before=`, so the file is
   the packaged unit without that line, with a header saying so. Every run of `install.sh`
   writes it again from the installed unit (run it after an NVIDIA update), and deletes it once
   the packaged unit no longer has the line. An override you wrote yourself is left alone.

It records what it replaced, and the NVIDIA 620 packages that were already installed, in
`/var/lib/n1x-kernel-ubuntu`.

## The kernel command line

- `acpi_osi="!Windows 2022"` (from proart-p16-linux) stays. Ubuntu's `linux-nvidia` kernel
  needs it to see the SSPM, and GRUB's command line is shared by every kernel. On this kernel
  it overrides Omarchy's `_OSI` quirk (1106), which exposes the SSPM the same way.
- No `mem_sleep_default=s2idle`: 1113 makes s2idle the default.
- No `power_wrap_drv.usb4_release=0`: 1112 makes that the default on N1x laptops.

## What --remove does

This reinstalls the NVIDIA packages that were there before (by name, at the version the
archive has now, e.g. Ubuntu's 615 and its prebuilt modules for `linux-nvidia`: the exact
versions from back then may be gone after a security update; prebuilt modules for a kernel
that has been removed since are left out, and the metapackage brings the current one's), purges
`nvidia-n1x-dkms-620-open`, the 620 user space (the 620 packages that were installed before
stay, and Ubuntu's `nvidia-dkms-620-open` comes back) and every `linux-image/headers-*-n1x*`
package, removes the apt pin, our nvidia-persistenced override and our `pci=` options, and
points GRUB's default back at the kernel that was running at install time (Ubuntu's
`linux-nvidia`; the newest installed one if that kernel is gone). The kernel command line and `GRUB_DEFAULT` go back to what they
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
