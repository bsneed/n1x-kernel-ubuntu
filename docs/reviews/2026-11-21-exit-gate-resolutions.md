# Resolutions: exit-gate review (2026-11-21)

How each finding of [2026-11-21-exit-gate.md](2026-11-21-exit-gate.md) was resolved on branch
`bsneed/review-fixes`, after `66ea5d5`. The F-IDs of the initial review are in
[2026-11-21-initial-resolutions.md](2026-11-21-initial-resolutions.md). Tests are in
`tests/t-*.sh` (`bash tests/run.sh`): 264 before this round, 315 after, all passing with 0
skipped in an ubuntu:26.04 container with shellcheck 0.11.0 and git, where shellcheck is clean.

| ID | Severity | Resolution | Commit |
|---|---|---|---|
| G1 | Blocker | Fixed. The first install records the packages it replaces and also the 620 packages already installed (`nvidia_before` in `scripts/lib-nvidia.sh`, which replaces the inline awk in install.sh; our DKMS package is never recorded). `--remove` then reinstalls Ubuntu's `nvidia-dkms-620-open` and removes only what the install added. New test (t-nvidia.sh, "had 620"): a pre-existing-620 fixture goes through the install's selection into `--remove`'s plan. With the old selection, 4 of its assertions failed: the plan removed `nvidia-driver-620-open`, `nvidia-kernel-common-620`, `nvidia-kernel-source-620-open`, `nvidia-utils-620`, `libnvidia-gl-620` and the firmware. | ffd2a5b |
| G2 | Should-fix | Fixed. `fallback_kernel` (lib-install.sh) keeps the recorded kernel while it has a vmlinuz and modules. Otherwise it picks the newest installed Ubuntu linux-nvidia kernel (version order, the same -64k flavour first). install.sh and `--remove` warn and update `previous-kernel`. `--remove` leaves out the prebuilt `linux-modules`/`linux-objects-nvidia-*-<k>` of a kernel that is gone (`nvidia_restore_wants`). `nvidia_prebuilt_kernel` covers `linux-objects-*` and no longer takes the metapackage `linux-modules-nvidia-615-open-nvidia` for a kernel named `nvidia`. Tests with a fake `MODULES_ROOT`/`BOOT_ROOT` (t-install.sh). | 6415397 |
| G3 | Should-fix | Fixed. `grub_keep_fallback` (lib-steps.sh) sets `GRUB_DEFAULT=saved`, runs update-grub and points `saved_entry` at the previous kernel right after the simulation, before the pin and the apt transaction. A kernel chosen with `--default` stays the default. `grub_default_is` makes that check fail when grub.cfg has no entry for the new kernel yet. Before, an empty `saved_entry` would have matched an empty id. The `dkms_all_kernels` message and docs/install.md now describe what happens. New tests/t-steps.sh, with logging stand-ins for update-grub, grub-editenv and grub-set-default. | f5cac4d |
| G4 | Should-fix | Fixed. `grub_back_to` (unset `next_entry`, set-default PREV) runs before `--remove` changes any package, and again after the final update-grub. **Deviation from the suggested placement:** it runs after the two apt simulations, not straight after the previous-kernel checks. A refused simulation says "nothing was changed", and moving saved_entry before it would make that untrue: a user's `--default` choice would be lost to a refusal. Every failure point the finding lists comes after the simulations. Tests in t-steps.sh. | 51cfcac |
| G5 | Nit | Fixed, differently from both suggestions. The simulation reads a copy of `/etc/apt/preferences.d` that holds the rewritten pin (`-o Dir::Etc::PreferencesParts`). The pin in /etc is written only after both simulations pass, so a refusal changes nothing, and there is no restore step that could itself fail. It was checked in the 26.04 container that apt honours an absolute `PreferencesParts` (a -1 pin there removes the candidate). | d21121c |
| G6 | Nit | Fixed. `update-initramfs` (install and remove), the kernel purge, and also the final `update-grub` of both paths, which were bare in the same way, die with a message. The message says where GRUB's default is and to run the same command again. Not unit-tested: it only adds messages to the orchestration. The container rehearsal below triggers the install and remove `update-initramfs` messages. | 5013b61 |
| G7 | Nit | Fixed. check.sh's verdict moves into `persistenced_status` (lib-nvidia.sh). It WARNs when the packaged unit no longer has the cycle but our generated override is still in /etc. Every branch is tested; the new case returned OK before. | 3f1d11e |

None was rejected or deferred.

The G1 test was also run against the old selection: with `nvidia_before` replaced by the old
inline awk (record only what the install replaces), 4 of the 315 tests fail ("had 620: every
620 package is recorded", "had 620: --remove takes away only what the install added", "had
620: --remove reinstalls Ubuntu's DKMS package and keeps the rest", "615 before: records what
it replaces and the 620 packages there").

Not covered by unit tests: G5 and G6, whose changes are in `install.sh`'s orchestration. The
rehearsal below runs both paths for real.

Out of scope, recorded in TODO.md (both pre-existing, seen in the rehearsal): `--remove`
removes rather than purges `nvidia-n1x-dkms-620-open` (dpkg keeps it as `rc`), and it leaves
`/lib/modules/7.3.0-n1x1` with Ubuntu's DKMS modules after purging 7.3.

## Container rehearsal

A real apt run of the old head (`66ea5d5`) and the new one (`3f1d11e`) on spark1, on a machine
that already ran Ubuntu's 620 (the G1 case).

- **Base:** `ubuntu:26.04` (arm64). `linux-image/headers/modules-7.0.0-1025-nvidia` from the
  archive, then `nvidia-driver-620-open` from `resolute-proposed` (620.73.04-0ubuntu0.26.04.1,
  16 packages of 620; its own DKMS build for 1025 ran). The `-proposed` source was then dropped
  again, as a user would. Stock `GRUB_DEFAULT=0`.
- **Stand-ins:** `update-grub` (writes a grub.cfg in grub-mkconfig's layout, newest kernel
  first), `grub-editenv`, `grub-set-default`, `grub-reboot`, `systemctl`, `uname -r`, and
  `update-initramfs` (which can be made to fail only when install.sh itself calls it). The
  kernel hooks `zz-update-grub` in `/etc/kernel/post{inst,rm}.d`, as grub2-common ships them,
  so the kernel package runs update-grub itself. The N1x GPU is a fake PCI device (`PCI_ROOT`).
- **Real:** apt, dpkg, the maintainer scripts and the DKMS builds of both 620 module packages for
  7.0.0-1025-nvidia and 7.3.0-n1x1. The packages are the ones built from `d6ec41b`/`4b9ab90`
  (`nvidia-n1x-dkms-620-open_620.73.04-n1x2`, `linux-image/headers-7.3.0-n1x1`); no packaging
  changed since.
- Both runs started from the same snapshot of the base.

### Old head (66ea5d5)

1. `install.sh`, with `update-initramfs` failing after the apt transaction: exit 1, with no
   message of its own (G6). GRUB then boots **7.3.0-n1x1 by default** (`GRUB_DEFAULT=0`, and
   the kernel package's update-grub made 7.3 entry 0): **G3 reproduced**.
2. `install.sh` again: exit 0. `nvidia-before` holds one line,
   `nvidia-dkms-620-open=620.73.04-0ubuntu0.26.04.1`.
3. `--remove`: exit 1. **G1 reproduced**, as the review inferred:

   ```
   nvidia-dkms-620-open : Depends: nvidia-kernel-source-620-open (<= 620.73.04-1) but it is not going to be installed
                          Depends: nvidia-kernel-common-620 (<= 620.73.04-1) but it is not going to be installed
   E: Unable to satisfy dependencies. Reached two conflicting assignments:
      1. nvidia-dkms-620-open:arm64=620.73.04-0ubuntu0.26.04.1 is selected for install
      2. ... Depends nvidia-kernel-source-620-open (>= 620.73.04)
         - nvidia-kernel-source-620-open:arm64 is selected for removal
   ERROR: apt cannot do this (see above): nothing was changed
   ```

   Despite "nothing was changed", the pin in /etc had lost its `nvidia-dkms-620-open` /
   `Pin-Priority: -1` stanza: **G5 reproduced**. Every re-run fails the same way.

### New head (3f1d11e)

1. `install.sh`, with `update-initramfs` failing after the apt transaction: exit 1, with
   `ERROR: update-initramfs failed (see above; is /boot full?). GRUB's default is still
   7.0.0-1025-nvidia (or 7.3.0-n1x1, if you chose it with --default); ...` (G6). `GRUB_DEFAULT=saved`
   and saved_entry were set before the apt transaction, so GRUB still boots **7.0.0-1025-nvidia
   by default** (G3 fixed).
2. `install.sh` again: exit 0; default 1025, a one-time boot of 7.3 pending. `nvidia-before` holds
   all 16 620 packages that were installed, `nvidia-dkms-620-open` among them, at their versions
   (G1).
3. `--default` (with `uname -r` saying 7.3.0-n1x1): exit 0; the default is 7.3.
4. `--remove` refused by its simulation (an extra, unknown package name appended to
   `nvidia-before`): exit 1, `E: Unable to locate package ... nothing was changed`, and the pin
   in /etc is byte-for-byte unchanged (G5 fixed). The default is still 7.3, the user's choice.
5. `--remove`, with `update-initramfs` failing after the NVIDIA restore. The restore itself
   succeeded: it asked for the 16 recorded 620 packages, apt found 15 of them already installed
   and put back only `nvidia-dkms-620-open` (which built its modules for 1025 again), and it
   removed only `nvidia-headless-no-dkms-620-open` and `nvidia-n1x-dkms-620-open`, the
   packages the install added. Then `update-initramfs` failed: exit 1, with `ERROR:
   update-initramfs failed ... The NVIDIA packages are back and GRUB boots 7.0.0-1025-nvidia
   by default; ...` (G6). The default was moved to 1025 before the restore, which took our
   modules away from 7.3, so it boots **1025**, not 7.3 (G4 fixed).
6. `--remove` again: exit 0. The NVIDIA packages were already as recorded, so its restore
   changes nothing. It purges `linux-image/headers-7.3.0-n1x1`; GRUB is back to
   `GRUB_DEFAULT=0`, booting 1025.

Correction (H6 of the [re-review](2026-11-21-exit-gate-rereview.md)): an earlier version of
this record put step 5's package changes under step 6, which contradicted step 5. There was
no snapshot reset between the two steps. The logs of the run weren't kept, so the order above
comes from the code, not a log. `update-initramfs` runs only after the restore's `apt-get` has
succeeded and the pin is removed, so its error in step 5 means the restore had already worked.
On the re-run, `nvidia_restore_removals` finds no 620 package outside `nvidia-before`, and our
DKMS package is gone.
7. Against the state before the install:
   - the NVIDIA and kernel packages (`dpkg-query`, name and version: the 16 620 packages,
     `libnvidia-egl-wayland1` and the four 1025 kernel packages) are **identical**: Ubuntu's
     620 is still installed (G1 fixed);
   - `/etc/default/grub` is identical;
   - `/var/lib/n1x-kernel-ubuntu`, the apt pin and the nvidia-persistenced override are gone;
   - the one leftover is `nvidia-n1x-dkms-620-open` in dpkg's `rc` state (see TODO.md).

G2 was not rehearsed: it needs a second linux-nvidia ABI and an autoremove. The tests with a
fake `MODULES_ROOT`/`BOOT_ROOT` cover it.

## Exit-gate re-review

How each finding of the [re-review](2026-11-21-exit-gate-rereview.md) (H1–H6) was resolved, after
`03b3903`. Tests: 315 before this round, 351 after, all passing with 0 skipped in ubuntu:26.04
(bash 5.3, shellcheck 0.11.0) and ubuntu:24.04 (bash 5.2, shellcheck 0.9.0, CI's lint), where
shellcheck is clean. Each regression test below was run and seen to fail on the code before its fix.

| ID | Severity | Resolution | Commit |
|---|---|---|---|
| H1 | Blocker | Fixed. `nvidia_restore_wants BEFORE PREV` asks for the same `linux-modules/objects-nvidia-NNN[-server]-open-` package for PREV, the kernel `--remove` goes back to, in place of a removed kernel's. It prints each name once and keeps -64k. The metapackage is no longer relied on. New t-install.sh tests use a proart-p16-linux-shaped `nvidia-before` (the per-ABI package, no metapackage): on the old code, 5 tests failed, and the fallback kernel got no 615 modules. If the archive has no such package, the restore simulation refuses. This was checked with real apt in ubuntu:26.04: `apt_simulate` on `linux-modules-nvidia-615-open-7.0.0-9999-nvidia` stops with `E: Unable to locate package ...` / `ERROR: apt cannot do this (see above): nothing was changed`, exit 1. The real `...-7.0.0-1026-nvidia` (resolute-proposed, priority 1) simulates fine. docs/install.md now says what happens. | 14c3ab8 |
| H2 | Should-fix | Fixed. The end of `--remove` moves into `remove_kernels` (lib-steps.sh), which purges first, then puts `GRUB_DEFAULT` back, then runs update-grub and `grub_back_to`. The kernel command line still goes back before the purge. A `GRUB_DEFAULT` that can't be read from `grub.before` now stops with a message instead of a silent `set -e` exit. t-steps.sh checks that the purge runs with `GRUB_DEFAULT=saved` and that a failed purge leaves it so. With the old order, 3 tests failed. docs/install.md is updated. | 3b68228 |
| H3 | Should-fix | Fixed. The G3 and G4 sequences move unchanged from install.sh into `install_packages` and `restore_packages` (lib-steps.sh). t-steps.sh drives both with an apt-get stand-in that logs the `GRUB_DEFAULT`, saved_entry and pin it ran with. Mutation probes: deleting `grub_keep_fallback` fails 7 tests, deleting `grub_back_to` fails 3, and moving either after apt fails 4 or 3. Deleting the pin copy fails 3. This corrects the G4 row's coverage claim above: the ordering was untested until now. Done before H2 and H4, so that their fixes had a test to fail first. | 1c304bc |
| H4 | Nit | Fixed. `restore_packages` runs `grub_back_to` before copying the rewritten pin into /etc. A test checks that the pin in /etc is unchanged when `grub_back_to` fails. It failed before the swap. | d5e015b |
| H5 | Nit | Fixed, all three. `dkms_all_kernels PREV` names the kernel GRUB boots, "(or 7.3.0-n1x1, if you chose it with --default)". The restore failure says GRUB now boots PREV, and how to keep 7.3 (`--default` after booting it). `grub-editenv - unset next_entry` dies with a message. Each message has a test, and mutants that drop them fail. | 46078d6 |
| H6 | Nit | Fixed. Step 6's package changes were step 5's restore. The steps are rewritten, with a note that the order comes from the code (the run's logs weren't kept). | 51d2b62 |

None was rejected.

Also in this round:

- The re-review's out-of-scope note: TODO.md and the `dkms_all_kernels` comment said DKMS builds
  only for the running and the newest kernel. 26.04's dkms 3.2.2-1ubuntu1 ships
  `autoinstall_all_kernels="yes"` (checked in the container), so both are corrected.
- Parked TODO (a): docs/install.md now says `--remove` *removes* our DKMS package and the 620
  user space. The behaviour is unchanged (`name-`). A purge of the 620 user space in the same
  transaction as 615's install could touch conffiles that 615 now owns, and this round has no
  rehearsal to check that. The TODO stays, as optional. (3445fa2)
- Parked TODO (b): not done. Purging the kernel before the NVIDIA restore would change the
  failure states that G4 and H2 rely on, and it needs its own rehearsal.

Still not covered by unit tests: the `update-initramfs` messages in install.sh's orchestration
(G6), which the container rehearsal above triggered. This round ran no new end-to-end
rehearsal: H1–H5 are covered by the tests above and by the real-apt simulation for H1.
