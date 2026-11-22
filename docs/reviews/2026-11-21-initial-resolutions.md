# Resolutions: initial review (2026-11-21)

How each finding of [2026-11-21-initial.md](2026-11-21-initial.md) was resolved on branch
`bsneed/review-fixes`. Tests are in `tests/t-*.sh` (`bash tests/run.sh`). The findings of the
exit-gate review that followed (G1–G7) are resolved in
[2026-11-21-exit-gate-resolutions.md](2026-11-21-exit-gate-resolutions.md).

| ID | Severity | Resolution | Commit |
|---|---|---|---|
| F1 | Major | Fixed. Only packages of another driver version (a three-digit branch in the name) and Ubuntu's `nvidia-dkms-620-open` are replaced (`nvidia_other_versions`, `nvidia_branch_of` in `scripts/lib-nvidia.sh`). The test uses a P16 + Docker package list: nvidia-settings, nvidia-prime, the container toolkit, libnvidia-container* and others stay. Before the fix that test failed, removing all of them. The apt simulation also stops the install if apt would remove anything else. | b30b501 |
| F2 | Major | Fixed. Every patch goes through `apply_patch` (`--forward --batch --fuzz=0`). A test applies a patch twice and expects the second to fail without reverting the file; with main's `--batch` it exited 0 and reverted it. | c2c3032 |
| F3 | Major | Fixed by setting, not refusing. `install.sh` sets `GRUB_DEFAULT=saved` (`grub_use_saved`), `--remove` puts the line from `grub.before` back unless the user changed it since (`grub_restore_default`), and `--default` refuses if it isn't saved. `grub_verify` checks that grub.cfg follows `saved_entry`. Main had no handling at all. Tests cover 0, saved, quoted, unset and a named entry. | 9a5e6e5 |
| F4 | Major | Fixed. Pin `620.73.04-*`; the user space is installed by name; control depends on `nvidia-kernel-common-620 (>= 620.73.04), (<= 620.73.04-1)` (Ubuntu's own range) and provides `nvidia-dkms-620-open (= 620.73.04)`. Every transaction is simulated first (`apt_simulate`, `apt_sim_check`). `--remove` reinstalls by name and keeps the pin until the restore worked. README/docs/install.md explain what the pin holds back. The test of main's pin text failed (exact revision). | b30b501, c19d508 (tests of control) |
| F5 | Major | Fixed. `dkms_all_kernels` dies when the build fails for any kernel with a `/boot/vmlinuz-*`. The preflight refuses to start if GRUB's fallback kernel, or a kernel losing prebuilt 615 modules, has no headers. With a stub dkms, main's function returned 0 after the fallback kernel's build failed. | b30b501 |
| F6 | Minor | Fixed. `cmdline_remove_pci VALUE BEFORE` restores `grub.before`'s command line exactly when it is unchanged since the install, and otherwise restores replaced values and keeps options the user had. Main turned `pci=hpmmioprefsize=64G` into nothing. | 9a5e6e5 |
| F7 | Minor | Fixed. `update-initramfs -u -k all` runs after the DKMS builds and after the restore. The postinst's refresh stays (the earlier stale-initramfs fix). | b30b501 |
| F8 | Minor | Fixed. Indented or exported assignments are refused (`grub_var_line`), so are `/etc/default/grub.d/*.cfg` files that replace either variable (`grub_dropin_overrides`; ones extending `$GRUB_CMDLINE_LINUX_DEFAULT`, like kdump-tools.cfg, pass). grub.cfg's linux line for the new kernel must carry the options (`grub_linux_args`, `cmdline_has_pci`). | 9a5e6e5 |
| F9 | Minor | Fixed. `grub_entry_id` tracks the submenu's braces and returns the bare id for top-level entries. Main returned rc=1. | 9a5e6e5 |
| F10 | Minor | Fixed. When `saved_entry` already is the new kernel (after `--default`), a re-run keeps it and says so. | 9a5e6e5 |
| F11 | Minor | Fixed. The .debs are taken by exact name. One whose version is installed with other files (md5sums compared, `deb_vs_installed`) stops the install with "raise the revision". The DKMS package now ships `DEBIAN/md5sums`. | b30b501, c19d508 |
| F12 | Minor | Fixed. `pkgbuild_info` reads pkgver, `_rcpatch`, the tarball and its sha256 and the patch list; build.sh stops unless they match `sources`. | c19d508 |
| F13 | Minor | Fixed by scoping. 0010 exempts only PCI 10de:2e03/2e06/2e13 (`RmIsN1xLaptopGpu` where the flag is set), so GB10 (DGX Spark) keeps 620's behaviour. `install.sh` refuses to run without one of those GPUs. The doc's wording was corrected (sample size, what the 615 claim rests on). NVIDIA_N1X_REVISION 2. | 158617b |
| F14 | Minor | Fixed. `secure_boot_enabled` (mokutil, else the EFI variable) stops the install; README says so. | b30b501 |
| F15 | Minor | Fixed. srcversion comparison, WARN when the journal is unreadable, pin checked through apt-cache policy's candidate. | bbb9edc |
| F16 | Minor | Fixed. The tested hardware is named precisely, with untested outputs (HDMI and more), the 60 Hz and hotplug issues, the -proposed dependency, the fallback's `GRUB_DEFAULT` need and what the pin means for security updates. | 2fcab6f, b30b501, 9a5e6e5 |
| F17 | Minor | Fixed. The package selection, restore plan, pin text, n1x kernel regex, PKGBUILD reading, DKMS templates (placeholders, sh -n, shellcheck of the maintainer scripts), `grub_entry_id` without a submenu, DKMS loop, apt simulation check and Secure Boot detection all have tests. | all |
| F18 | Minor | Fixed. build.sh refuses a dirty checkout (`--allow-dirty` to override, which marks the commit `-dirty`) and a non-git one, and records the commit in `out/SOURCE` and the DKMS package's `SOURCE`. | c19d508 |
| F19 | Nit | Fixed: one `grep -q`. | b30b501 |
| F20 | Nit | Fixed: the header comment says what triggers `debs`. The actions are pinned by commit (checkout v7.0.1, upload-artifact v7.0.2). The workflow also runs on pushes to every branch: before, only main ran it, despite the header. | d6ec41b |
| F21 | Nit | Fixed: `need_arg` in install.sh, build.sh and nvidia-dkms.sh. | b30b501, c19d508 |

Found while verifying, not in the review: on an Ubuntu 26.04 without a C++ compiler the DKMS
build failed (the modules' build runs g++), so `nvidia-n1x-dkms-620-open` now depends on `g++`
(4b9ab90). An end-to-end install, re-run and `--remove` in an ubuntu:26.04 container with the
real 615 stack, nvidia-settings and nvidia-prime (GRUB and initramfs stubbed) restored
`/etc/default/grub` byte for byte and the 615 packages at their exact versions.

On rtx24 (ProArt P16, 10de:2e06, installed earlier by main's `install.sh`), 2026-11-21:
- A re-run installed DKMS n1x2 and kept 7.3 as the default (F10).
- The generated persistenced override's body is byte-identical to the hand-made one.
- After the reboot, PID 1 logged no ordering cycle.
- An s2idle `pm_test=devices` cycle succeeded (`suspend_stats` success=1, fail=0, no
  "PM suspend notifier failed").
- A spark1 rebuild of the installed kernel deb was flagged as differing (F11).
- `--remove` brought back 615 at the exact versions, the user's command line and the 1026-nvidia
  default, and left the third-party apt files and nvidia-vaapi-driver alone.
- 1026-nvidia then booted with 615 and no PID 1 warnings.
- The reinstall's one-time boot ran 7.3 while the saved default stayed 1026 until `--default`.
- `check.sh` gave 20 OK, 1 WARN (no dock), 0 FAIL.

Also from TODO.md on the same branch: the nvidia-persistenced ordering-cycle override
(7a396ae), the README's AppArmor differences, the install prerequisites and the sssd FAQ
(2fcab6f).
