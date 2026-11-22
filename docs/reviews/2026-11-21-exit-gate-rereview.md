# Review: n1x-kernel-ubuntu, re-review of the exit-gate fix round (G1–G7)

Follow-up to [2026-11-21-exit-gate.md](2026-11-21-exit-gate.md) (G1–G7), and a check of its
[resolution record](2026-11-21-exit-gate-resolutions.md).

## Summary

This round fixes G1–G7, and the helper-level fixes are real: the suite runs 315 passed,
0 failed, 0 skipped, shellcheck is clean, and mutating each fixed helper fails its new tests.
The round does **not** pass the gate, because one fix creates a new way to lose the NVIDIA
driver:

- **H1 (blocker, introduced by G2's fix):** `nvidia_restore_wants` drops the 615 prebuilt
  modules of a kernel that has been removed. It assumes the metapackage
  `linux-modules-nvidia-615-open-nvidia` will bring the modules for the current kernel.
  proart-p16-linux, the project's main route, installs only the per-ABI package and never the
  metapackage. On that route `--remove` finishes and reports success, but the fallback
  kernel has no NVIDIA driver.
- On 66ea5d5, the same situation made `--remove` stop before it changed anything.

Two should-fix findings remain:

- **H2:** G4 leaves a gap on stock GRUB. `--remove` puts `GRUB_DEFAULT=0` back before it
  purges the kernel.
- **H3:** nothing tests the ordering that G3 and G4 depend on.

Both parked TODOs are rightly TODOs, not blockers.

## Scope and Evidence

- **Date / description:** 2026-11-21. This is a scoped re-review of the exit-gate fix round,
  not a full pass.
- **Reviewed range:** `66ea5d5897c79192df458e66f6869aac4eca7690..03b3903250dadf1f54bd2b8550be1e45cda8b4bb`.
  The commits are ffd2a5b (G1), 6415397 (G2), f5cac4d (G3), 51cfcac (G4), d21121c (G5),
  5013b61 (G6), 3f1d11e (G7), b43269a (docs) and 03b3903 (shellcheck 0.9). The range also
  contains 0ba2b9f, which adds the exit-gate report.
- **Uncommitted inputs:** none. `git status --porcelain` was empty, and HEAD was 03b3903 before
  this report was written. This report is the only new file, and it is untracked.
- **Files read in full:**
  - `scripts/install.sh`, `lib-install.sh`, `lib-nvidia.sh`, `lib-steps.sh` and `grub.sh`;
  - the relevant parts of `check.sh`;
  - `nvidia-dkms/{prerm,postrm}`;
  - the diffs of `tests/t-install.sh`, `t-nvidia.sh` and the new `t-steps.sh`;
  - `tests/run.sh`, TODO.md and docs/install.md.
- **Also read, for context:** proart-p16-linux `install/01-kernel.sh` and `install/02-nvidia.sh`.
- **Context limitation:** I read the exit-gate report first, as the brief directs. I formed
  initial findings from the code before reading the resolution record. The brief already
  summarised the G4 deviation and the two TODOs.

### Commands and results

- **Tests:** `bash tests/run.sh` in an `ubuntu:26.04` container on spark1, with bash 5.3.9,
  shellcheck 0.11.0, git 2.53 and patch. The input was a `git archive 03b3903` copy, committed
  into a fresh git repo:
  - `tests: 315 passed, 0 failed, 0 skipped`, exit 0;
  - this matches the resolution record's count.
- **shellcheck 0.11.0** on `scripts/*.sh tests/*.sh nvidia-dkms/{postinst,prerm,postrm}`: exit 0,
  no output.
- **CI:**
  - Run 44980609189 (lint) on 03b3903 succeeded.
  - b43269a failed (run 44980509849), the SC2317 case that 03b3903 fixes.
  - I did not run shellcheck 0.9.0 myself; CI's lint job uses it.
- **G5 mechanism:** I checked it in the container. With a copy of preferences.d holding a -1
  pin for `hello`, `apt-cache policy -o Dir::Etc::PreferencesParts=<copy> hello` showed
  `Candidate: (none)`, and `apt-get -s ... install hello` failed. Without the override the
  candidate is 2.10-5build1.
- **DKMS behaviour on 26.04:** I extracted `dkms_3.2.2-1ubuntu1` and
  `nvidia-dkms-620-open_620.73.04-0ubuntu0.26.04.1` from resolute(-proposed).
  - `nvidia-dkms-620-open`'s postinst calls `/usr/lib/dkms/common.postinst`.
  - dkms ships the conffile `/etc/dkms/framework.conf.d/autoinstall_all_kernels.conf` with
    `autoinstall_all_kernels="yes"`, so the build covers every kernel with headers.
  - A build failure makes the postinst `exit $res` (non-zero).
- **Archive:** `linux-modules/objects-nvidia-615-open-7.0.0-10{23..26}-nvidia` exist per ABI.
  The metapackage `linux-modules-nvidia-615-open-nvidia` exists too, but proart-p16-linux
  never installs it (`01-kernel.sh:41-46`, `02-nvidia.sh:20-29`).
- **Mutation probes:** each mutant was applied to a fresh copy inside the container, and the
  full suite was run.

  | Mutant | Result |
  |---|---|
  | G1: `nvidia_before` back to the old selection (replaced only) | 4 fail (as the record says) |
  | G2: `kernel_installed` checks only `/lib/modules/<k>` | 2 fail |
  | G2: `fallback_kernel` ignores the -64k flavour | 2 fail |
  | G2: `nvidia_restore_wants` keeps everything | 2 fail |
  | G3: `grub_keep_fallback` ignores a `--default` choice | 1 fail |
  | G7: stale override reported OK | 1 fail |
  | G3: `grub_keep_fallback "$prev"` deleted from install.sh | **0 fail** |
  | G4: the early `grub_back_to "$prev"` deleted from do_remove | **0 fail** |
  | G5: rewritten pin written to /etc before the simulation | 0 fail (disclosed as untested) |
  | G6: `update-initramfs … \|\| die` replaced by `\|\| true` | 0 fail (disclosed as untested) |

- **Cleanup:** I removed the `rr-n1x-review` container and `/tmp/rr-n1x` on spark1, and left
  `n1xlint` alone. Nothing was run on rtx24.

### Not done or unverified

- I ran no real install or `--remove`. The container rehearsal in the resolution record is
  the implementer's evidence, and I did not reproduce it.
- H1 is shown by inspection and from archive metadata, not by a run.
- H2's trigger (a purge failure, then an `update-grub` before the re-run) is shown by
  inspection.

## Prior finding resolutions (G1–G7)

| ID | Status | Evidence |
|---|---|---|
| G1 | **Fixed** | `nvidia_before` (lib-nvidia.sh:45-54) records the replaced packages and every installed 620 package, but never ours. It is called at install.sh:122. The t-nvidia.sh "had 620" round trip goes through the real selection functions. The old-selection mutant fails 4 tests. |
| G2 | **Fixed as described, but the fix introduces H1** | `fallback_kernel` (lib-install.sh:121-142) is used at install.sh:88 and :173, and `previous-kernel` is now rewritten on every run (install.sh:125). `nvidia_prebuilt_kernel` no longer takes the metapackage to be a kernel. The tests are mutation-resistant. The `want` filter's premise is wrong for proart-p16-linux machines: see H1. |
| G3 | **Fixed; the ordering is untested (H3)** | `grub_keep_fallback` (lib-steps.sh:77-83) runs at install.sh:128, before the pin and the apt transaction. `grub_default_is` fixes the empty-id match. The lib-install.sh:187 wording is corrected but still imprecise (H5). The placement is proven only by the rehearsal. |
| G4 | **Fixed for saved_entry; GRUB_DEFAULT gap (H2); ordering untested (H3)** | `grub_back_to` runs at install.sh:205, before the restore, and again at :232. **The deviation is sound:** the simulations (install.sh:198-199) change nothing a boot depends on, and moving saved_entry before them would discard a `--default` choice whenever a simulation refused. Every failure point G4 lists comes after :205. One small leftover: the pin is copied into /etc at :200, before `grub_back_to` (H4). |
| G5 | **Fixed** | The simulation reads `$TMP/prefs` (install.sh:190-198), and /etc is written only after both simulations (:200). I verified that apt honours `PreferencesParts`. Untested, as disclosed. |
| G6 | **Fixed** | `\|\| die` at install.sh:136-137, :143, :210-211, :228-229 and :231. The messages match the state, except for H2's window. One bare step remains: `grub-editenv - unset next_entry` in `grub_back_to` (lib-steps.sh:87), pre-existing (H5). |
| G7 | **Fixed** | `persistenced_status` (lib-nvidia.sh:131-150) is called at check.sh:112-113. Every branch is tested, and the stale-override mutant fails. |

**Unresolved prior findings:** none as such. H1 and H2 are new findings in code the G2 and G4
fixes touch.

## Checklist Results

### 1. Panic & Crash Paths

No issues found in the changed code.

- With `set -euo pipefail`, the `x=$(f) || die` forms (install.sh:88, :173; lib-steps.sh:79)
  are sound.
- `"${s%% *}" "${s#* }"` in check.sh always calls OK or WARN, because `persistenced_status`
  always prints one of them.
- `fallback_kernel` prints nothing on failure (tested).
- The empty `want`, `remove` and `kpkgs` arrays under `set -u` are fine on bash 5.x.

### 2. Concurrency & Thread Safety

Not applicable: nothing runs in parallel beyond apt and dpkg's own lock.

### 3. Resource Management

No issues found. `$TMP/prefs` sits under `$TMP`, which the EXIT trap removes.

### 4. Error Handling & System Boundaries

- **H4 (nit):** the pin is rewritten before `grub_back_to`.
- **H5 (nit):** two messages are imprecise, and one step still exits without a message.

### 5. Input Validation & Security

No issues found. No new capabilities or dependencies. The new paths are fixed paths, or come
from kernel release names in `/lib/modules` and `/boot`.

### 6. Semantic Correctness

- **H1 (blocker).**
- **H2 (should-fix).**
- Parked TODOs (a) and (b): assessed below as rightly TODOs.

### 7. Architecture & Design

No issues found.

- The new helpers sit in the right layer: pure helpers in lib-nvidia.sh and lib-install.sh,
  GRUB side effects in lib-steps.sh.
- install.sh stays orchestration only, at 238 lines.
- Every changed file is under 300 lines.

### 8. Test Quality

- **H3 (should-fix):** the G3 and G4 orderings are untested.
- **H6 (nit):** the rehearsal record contradicts itself in steps 5–6.
- The H1 fixture (t-install.sh:460-467) contains the metapackage. That is the assumption that
  hides H1: a fixture shaped like a proart-p16-linux machine would have shown it.

### 9. Code Organization

No issues found.

## Findings

### H1 — Blocker (correctness, introduced by the G2 fix) — `--remove` leaves the fallback kernel without NVIDIA modules on a proart-p16-linux machine

- **Location:**
  - `scripts/lib-install.sh:144-160` (`nvidia_restore_wants`), called at `scripts/install.sh:183`;
  - the claim at `docs/install.md:71-73`;
  - the fixture at `tests/t-install.sh:460-467`.
- **Violated requirement:** README and docs/install.md "Remove" say it "reinstalls the NVIDIA
  packages that were there before (… Ubuntu's 615 and its prebuilt modules …; prebuilt modules
  for a kernel that has been removed since are left out, **and the metapackage brings the
  current one's**)". The install's own invariant, enforced by `dkms_all_kernels`, is that the
  fallback kernel must have a GPU driver. On the N1x, the NVIDIA GPU is the only display
  engine.
- **What happens:**
  - proart-p16-linux installs `linux-modules-nvidia-615-open-$KREL` by name (`01-kernel.sh:46`),
    with the 615 user space and no metapackage.
  - So on the P16 route, `nvidia-before` holds `linux-modules-nvidia-615-open-<k>` and
    `linux-objects-nvidia-615-open-<k>`, but not `linux-modules-nvidia-615-open-nvidia`.
  - When `<k>` is no longer installed, `nvidia_restore_wants` warns and drops both packages.
  - Nothing brings 615 modules for the new `prev` (`fallback_kernel`'s choice).
  - The restore then removes our DKMS package, and its prerm runs `dkms remove --all`.
  - `--remove` ends with "Removed. GRUB boots $prev by default again".
  - `prev` boots with 615 user space and no `nvidia.ko`.
- **Regression:** on 66ea5d5, `--remove` died at the `previous kernel … is no longer installed`
  check, before it changed anything. The fix turns a safe refusal into a run that reports
  success without a driver.
- **Failure scenario:**
  1. A P16 user installed with proart-p16-linux (KREL 1026), then ran install.sh.
  2. Later they re-ran proart's `01-kernel.sh` for a newer linux-nvidia, 1030. That installs the
     1030 image and headers, and the DKMS kernel hook builds our modules for 1030.
  3. They removed 1026 as proart's header says (`apt remove linux-image-$KREL …`).
  4. `install.sh --remove` picks 1030 and leaves out the 1026 modules. No metapackage is
     recorded, so 1030 ends up with no NVIDIA modules.
  5. The next boot has only the EFI framebuffer.
- **Evidence:** inspection, the proart-p16-linux scripts and archive metadata. Not reproduced
  with a run.
- **Fix:**
  - When `nvidia_restore_wants` drops `linux-(modules|objects)-nvidia-NNN-open-<gone>`, print
    the same package for `prev` instead (pass `prev` in, and dedupe).
  - If the archive doesn't have it, the existing simulation stops with "nothing was changed".
  - Alternatively, die when `want` would leave `prev` with no prebuilt 615 modules and no
    metapackage.
  - Add a test with a P16-shaped `nvidia-before` that has no metapackage.

### H2 — Should-fix (safety, G4 incomplete) — `--remove` puts `GRUB_DEFAULT=0` back before purging the kernel

- **Location:** `scripts/install.sh:216-223` (`grub_restore_default` at :220) vs the purge at
  :225-230. The comment at :202-203 and `docs/install.md:83-84` ("a failure partway through
  still boots that kernel") both make that claim.
- **What happens:**
  - On a machine that had stock `GRUB_DEFAULT=0`, `/etc/default/grub` gets `GRUB_DEFAULT=0` back
    while 7.3 is still installed. After the restore, 7.3 has no NVIDIA modules (615 case).
  - If the purge fails (`die` at :228-229, "GRUB boots $prev by default"), grub.cfg still says
    `default="${saved_entry}"`, which is prev.
  - Any `update-grub` before the re-run regenerates grub.cfg with `default="0"`, which is 7.3,
    the newest version. Examples: a kernel or grub update from unattended-upgrades, or
    `apt -f install` reconfiguring the half-purged image.
- **Failure scenario:**
  1. On a non-P16 N1x laptop with stock GRUB, the linux-image prerm fails during the purge.
  2. The next day, unattended-upgrades installs a linux-nvidia update, and its postinst runs
     update-grub.
  3. The laptop then boots 7.3 by default, with no NVIDIA driver, against what the die message
     said.
  - This needs two events and only applies to stock GRUB. The machine still boots, and a
    `--remove` re-run fixes it.
- **Fix:** move `grub_restore_default` after the kernel purge, just before the final
  `update-grub` at :231. The cmdline restore can stay where it is. The purge's own update-grub
  then still renders `saved_entry`.

### H3 — Should-fix (test quality) — the orderings that fix G3 and G4 are untested

- **Location:** `scripts/install.sh:128` and `:205`. The resolution record says "Tests in
  t-steps.sh" for G4, and lists only G5 and G6 as not unit-tested.
- **What happens:** t-steps.sh tests `grub_keep_fallback` and `grub_back_to` in isolation.
  Deleting either call from install.sh leaves all 315 tests passing (mutation probes above).
  Yet the placement *is* the fix for both safety findings, and the rehearsal can't be repeated
  in CI.
- **Fix:** the cheapest option is an order test over install.sh:
  - `grub_keep_fallback` before `"${APT[@]}" "${args[@]}"`;
  - `grub_back_to` before the restore `"${APT[@]}" install "${want[@]}"`.
- It is a textual gate, weak but cheap. Better is a stubbed-orchestration test of
  do_install/do_remove that logs the order of calls, as t-steps.sh does for its functions.
  Either way, correct the record's coverage claim.

### H4 — Nit (error handling) — the rewritten pin reaches /etc before `grub_back_to` can fail

- **Location:** `scripts/install.sh:200` vs `:205`.
- **What happens:** if `grub_point` dies ("no GRUB entry for $prev", for example because
  grub.cfg is stale for a just-installed fallback kernel), the pin in /etc has already lost its
  -1 stanza. That is G5's state, reached by a narrower path.
- **Fix:** swap the two: call `grub_back_to` first, then copy the pin.

### H5 — Nit (messages) — some messages don't match the state

- `scripts/install.sh:207-208`: the restore-failure message doesn't say that GRUB's default
  is now `$prev`. A user who chose 7.3 with `--default` and decides to stay on it needs to know
  to run `--default` again.
- `scripts/lib-install.sh:187` says "GRUB's default is still the kernel you ran before the
  install". That is wrong after `--default` (it's `$RELEASE`) and after a G2 fallback (it's the
  fallback). install.sh:137 already words it correctly.
- `scripts/lib-steps.sh:87`: `grub-editenv - unset next_entry` still exits under `set -e` with
  no message (pre-existing; G6 class).

### H6 — Nit (record) — the rehearsal's steps 5 and 6 contradict each other

- **Location:** `docs/reviews/2026-11-21-exit-gate-resolutions.md:90-98`.
- **What happens:**
  - Step 5 says the NVIDIA restore succeeded ("The NVIDIA packages are back") and that only
    `update-initramfs` failed.
  - Step 6 says the re-run "puts back only `nvidia-dkms-620-open`" and removes
    `nvidia-n1x-dkms-620-open`. Step 5's restore would already have done both.
- Either the snapshot was reset between the two steps or one of them is misdescribed. I could
  not reconcile them. Correct the record. I don't take it as evidence against G4 or G6, which
  step 5 alone covers.

## The two parked TODOs

### (a) `nvidia-n1x-dkms-620-open` is removed, not purged

Not a correctness issue, so a TODO is right.

- The package has no conffiles, and its postrm acts only on `remove` (update-initramfs). A
  purge would do nothing beyond dropping dpkg's `rc` record.
- `rc` packages' relationships aren't considered by apt.
- The repo's own selectors ignore `rc`: `dpkg_installed` takes `ii`, and `n1x_kernel_pkgs`
  takes `[ir][iHUFWt]`.
- It is pre-existing: main also used `name-`.
- The wording at `docs/install.md:73-76` ("purges … the 620 user space") is wrong for the 620
  user space too, since it is removed with `-` as well.
- The fix is trivial: use `"${remove[@]/%/_}"` (apt's purge suffix; `apt_sim_check` already
  accepts `Purg`), or say "removes".

### (b) `/lib/modules/7.3.0-n1x1` keeps Ubuntu's DKMS modules after the purge

Residue, not a correctness issue, so a TODO is right.

- It only happens in the had-620 case.
- With no vmlinuz left, 7.3 is not in GRUB, `kernels_bootable` or `fallback_kernel`.
- A later reinstall replaces `nvidia-dkms-620-open`, whose prerm runs `dkms remove --all`.

There is one more reason to do the TODO's suggested reorder (purge the kernel packages before
the NVIDIA restore):

- On 26.04, dkms ships `autoinstall_all_kernels="yes"`, so Ubuntu's postinst builds stock
  620.73.04 for 7.3 as well, and a build failure fails the postinst.
- So the had-620 `--remove` succeeds only while stock 620 still builds against our kernel. It
  does today: the rehearsal built it.
- A later kernel bump that broke it would block `--remove` on every re-run, because the purge
  comes after the restore.
- Purging first removes that dependency and the residue. It is safe: the GRUB default is
  already prev, and prev keeps our modules until the restore.

### Out-of-scope observation

TODO.md:91-93 and lib-install.sh:163 say DKMS's `common.postinst` builds "only for the running
and the newest kernel". That is not true of 26.04's dkms 3.2.2-1ubuntu1, whose shipped
`autoinstall_all_kernels.conf` makes it build for every kernel with headers. `dkms_all_kernels`
is still worth keeping: it is the check that fails loudly. But the comment and the TODO item
should be corrected.

## Severity Summary

- **Blocker (correctness/safety):**
  - H1 `scripts/lib-install.sh:144-160`, `scripts/install.sh:183`, `docs/install.md:71-73`
- **Should-fix:**
  - H2 `scripts/install.sh:216-231`, `docs/install.md:83-84`
  - H3 `scripts/install.sh:128,205`, tests
- **Nit:**
  - H4 `scripts/install.sh:200-205`
  - H5 `scripts/install.sh:207-208`, `scripts/lib-install.sh:187`, `scripts/lib-steps.sh:87`
  - H6 `docs/reviews/2026-11-21-exit-gate-resolutions.md:90-98`
- **TODOs (a) and (b):** rightly TODOs. For (a), fix the wording at `docs/install.md:73-76`
  either way.

**Exit gate: not passed.** H1 is a new correctness issue that this round introduced. H2 is a
remaining safety gap in G4.

## What's Done Well

- **G1** replaces the untested inline awk with a function. The round-trip test feeds a
  pre-existing-620 fixture through the real selection functions, which is exactly the coverage
  gap the exit gate named.
- **G5's fix** is better than either suggested one. The simulation reads a copy of
  preferences.d, so no restore step can itself fail, and apt does honour it (verified).
- **The G4 deviation** was reasoned about, not just taken. Keeping simulation refusals truly
  side-effect-free preserves a user's `--default` choice.
- **`grub_default_is`** catches the empty-saved_entry-matches-empty-id bug that the old inline
  comparison had.
- **`fallback_kernel`** requires a vmlinuz, not just a `/lib/modules` directory. The test
  covers DKMS leftovers, half-removed images, version order (999 against 1030), flavour and the
  case with no kernel at all.
- **The old-vs-new container rehearsal** with real apt, dpkg and DKMS is strong evidence, and
  it reproduced G1, G3 and G5 on the old head before showing them fixed.
