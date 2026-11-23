# Review R2: i2c-hid probe retry on the ProArt P16 (PR #3), re-review of fix round 1

Follow-up to [2026-11-23-i2c-hid-probe-retry-initial.md](2026-11-23-i2c-hid-probe-retry-initial.md)
(R1-01–R1-07). It also checks R1's
[resolution record](2026-11-23-i2c-hid-probe-retry-initial-resolutions.md).

## Summary

This round adds four things:

- a C harness that runs 0002's patched code against a fake device;
- a new retry schedule (5 s between attempt starts, with `probe_retry_next`);
- disabling wakeup on a deferred device;
- doc and test fixes.

**This round found no new correctness or safety issue in the kernel code.** I traced the new
schedule, the resume requeue, the jiffies wrap, and the wakeup disable/enable against the 7.3
tree's `wakeup.c`, `wakeirq.c`, `i2c-core-base.c` and `workqueue.c`. All of them are correct
for remove, shutdown, suspend, freeze, thaw, poweroff and restore in every state.

The harness is real:

- It extracts the code from the fixture with 0002 applied.
- Its fakes match 7.3 semantics or are stricter.
- It builds warning-free with gcc 13, clang 18 and Apple clang 17.
- ASan and UBSan are clean (gcc and Apple clang).
- It kills every mutant I spot-checked or added, except one that is equivalent in practice.

Six of R1's seven findings are verified resolved. R1-02 stays open: it is a contract deviation
waiting for the owner, and the code and docs now describe it accurately.

There are three new findings, none of them correctness or safety:

- **R2-01 (Minor):** writes to `power/wakeup` while a retry is pending undo R1-04's fix in both
  directions.
- **R2-02 (Nit):** two faked stock functions are not pinned.
- **R2-03 (Nit):** the harness's failure messages swap "expected" and "actual" when the
  expected value is empty.

3 findings: 0 Critical, 0 Major, 1 Minor, 2 Nit.

## Scope and Evidence

- **Date / description:** 2026-11-23, R2 (re-review of fix round 1) of loop run
  2026-11-23-i2c-hid-probe-retry, draft PR #3.
- **Base of the PR:** `f44fc16ed106acb5f7fa93b1af53b32da81c9a33` (origin/main).
- **R1 reviewed:** `e00a55250baabd8a2d7b1f456173317d4c980d96`.
- **Head:** `8db389233a3306973f130531fde5baf82564cab8`. This round's range is `e00a552..8db3892`,
  and I also re-read what the fixes touch.
- **Commits in the range:**
  - `3a433a58846cb6230256d563bbab2014fba49c80`: truncated `.ko.zst`/`.ko.xz` tests (R1-07).
  - `d8ae393acac4a9b20c7cb3aa14c4f15928960428`: the harness (R1-01).
  - `f6fc44a88d3afd5863d4a5afc2f5b7f26cff9427`: the retry schedule (R1-03).
  - `42d1ee20a74f680ce73b2da9b16aaa7e9385d231`: the wakeup disable (R1-04).
  - `04ce2b7b820e9a76defd3d3a864cb24e166379b2`: header and doc wording (R1-02, R1-05, R1-06).
  - `8db389233a3306973f130531fde5baf82564cab8`: the R1 report and the resolutions (docs only).
- **PR state:** `gh pr view 3` gives headRefOid `8db3892…` and isDraft true. `gh pr checks 3`
  shows lint passing in both runs, which are a push and a pull_request run on `8db3892`, and
  debs skipping. The lint job log says `tests: 676 passed, 0 failed, 0 skipped`, so CI ran the
  harness with no skip. (Locally the count is 673 plus 1 skip, because a `git archive` has no
  git.)
- **Uncommitted inputs:** none. `git status --porcelain --untracked-files=all` in the worktree
  (detached at `8db3892`) was empty before this report was written. This report is the only
  new file.
- **Contract:** the owner's brief (unchanged since R1). The repo has no AGENTS.md or REVIEW.md.
- **Order of reading:** I read the diff, the patch, the harness and the 7.3 sources, and noted
  my own findings before I read the R1 report and the resolutions. I did see the fixer's
  commit subjects first.

### Commands and results

- **Tree fidelity (`w1-i2chid`):**
  - I copied the fixture, applied 0002 with `patch -Np1 --fuzz=0`, and ran `cmp` against
    `/k/linux-7.3/drivers/hid/i2c-hid/i2c-hid-core.c`: `TREE_MATCHES_FIXTURE_PLUS_0002`.
  - I reverse-applied 0002 (`-R --fuzz=0`) to a copy of the tree's file: the result is equal
    to the fixture.
  - So the container already held 8db3892's 0002 on top of Omarchy and 0001, and I didn't
    need `/k/r2`. The suite's "0002 applies after Omarchy and 0001" passes too.
- **Build:** `make -j4 W=1 M=drivers/hid/i2c-hid`, with the core file touched, recompiled all
  six objects with **0 compiler warnings and 0 errors**.
  - modpost then fails with "symbol … undefined" for every symbol, including stock ones, because
    the tree has no `Module.symvers`. That is the same baseline limit R1 recorded.
  - The resolution record's "0 compiler warnings" is accurate, but it doesn't mention modpost.
  - The tree's `.config` has `HZ=250`, `PM_SLEEP=y`, `DMI=y` and `I2C_HID_CORE=m`.
- **checkpatch:** `scripts/checkpatch.pl --no-tree --strict` on 0002 reported 0 errors,
  0 warnings and 0 checks (353 lines).
- **Suite (`w1-lint`: bash 5.2.21, shellcheck 0.9.0, gcc 13.3.0, clang 18.1.3):** I ran it on a
  `git archive` of 8db3892.
  - `bash tests/run.sh` printed `tests: 673 passed, 0 failed, 1 skipped` and exited 0. The skip
    is `source_commit: no git`.
  - To confirm the harness ran, I used a runner that executes only `tests/t-i2c-hid-retry.sh`
    and lists every `eq`. With gcc it gave 219 passed, 0 failed, 0 skipped: 8 harness gates
    plus 211 `retry:` checks, `DONE 211`, and "builds with cc". With `CC=clang` the result was
    identical ("builds with clang").
- **Harness, stricter builds:**
  - `-Wall -Wextra` (minus unused-parameter, sign-compare and missing-field-initializers): no
    warnings with gcc or clang.
  - `-fsanitize=address,undefined` with gcc: clean, exit 0, and the output is identical to the
    suite's.
  - clang 18 in the container lacks the ASan runtime, so I couldn't run sanitizers there.
- **Harness on macOS (Apple clang 17.0.0):** it builds with the suite's flags and no
  diagnostics. Its output is identical to the Linux output, with no CHECK mismatches, and
  ASan/UBSan are clean.
- **Lint:** `bash -n` on every `scripts/*.sh` and `tests/*.sh` was clean. CI's exact command,
  `shellcheck scripts/*.sh tests/*.sh nvidia-dkms/postinst nvidia-dkms/prerm nvidia-dkms/postrm`,
  exited 0, and so did `shellcheck -x scripts/*.sh tests/*.sh`.
- **AI attribution:** a grep of the six commit bodies and the diff for
  claude/anthropic/co-authored/generated found only the review documents' own description of
  that grep.
- **File sizes:**
  - The harness files are 139 to 266 lines, and `t-i2c-hid-retry.sh` is 88.
  - The patch is 440 lines and the R1 report 499; both are documents, not code files.

### Mutants (isolated copies in `w1-lint`, full suite)

Each mutant edits one `+` line of 0002, and the script checks that exactly 1 line changed. I
spot-checked the fixer's claims and added mutants of my own.

| Mutant | Change | Result (failures) | Fixer's claim |
|---|---|---|---|
| M2 | `_resume`: `case GAVE_UP` → `case NONE` | killed (8) | 8 ✓ |
| N5 | wakeup not disabled when deferring | killed (28) | 28 ✓ |
| N13 | RESET to the current `hdesc.wCommandRegister` | killed (1) | 1 ✓ |
| S2 | `i2c_hid_has_retry` checks only grep's status | killed (2) | 2 ✓ |
| X1 | `_queue` without the clamp (`next - now` when `next` has passed) | killed (2) | new |
| X3 | `probe_retry_wakeup = false` (never re-enabled) | killed (28) | new |
| X6 | `_stop` doesn't call `cancel_delayed_work_sync` | killed (6) | new |
| X9 | the work doesn't store `probe_retry_next` | killed (13) | new |
| X12 | `_stop` returns early unless PENDING | killed (10) | new |
| X13 | the retry ignores `power_up` | killed (41) | new |
| X14 | `probe_retry` true on every machine | killed | new |
| X11 | RESET gate `!hid->version` → `!hid->vendor` | **survives** | new |

X11 is equivalent on any real device. `vendor` and `version` are set together, from the same
validated descriptor, in `__i2c_hid_core_probe`. The two differ only for a device whose vendor
ID is 0x0000, and none of the P16's devices has one (0B05, 222A, 093A). So it is not a test
defect.

### Probes

- **R2-01 demo:** a copy of `harness.c` with its own `main`, built against the extracted
  patched code on macOS, simulated `power/wakeup` writes during PENDING. Results are under
  R2-01.
- **IFS check:** `printf 'CHECK\tn\t\tfoo\n' | while IFS=$'\t' read -r a b c d` gives
  `want=[foo] got=[]`. X14's real failure output shows the effect: see R2-03.

### Not verified

- Anything on the P16: recovery, attempt durations, whether these GpioInts are wake-capable
  (`power/wakeup` on rtx24), and so whether R1-04 or R2-01 matter there in practice.
- Linking the full `i2c-hid.ko` (no `Module.symvers`), sparse and smatch.
- Clang ASan on Linux (no runtime in the container).
- `t-i2c-hid-retry.sh` under macOS's bash 3.2, which the resolutions claim. I ran the harness
  binary on macOS, not the shell script.

## Checklist Results

### 1. Panic & Crash Paths

No issues found.

- **Kernel:** the new code does unsigned jiffies arithmetic only through
  `time_after`/`time_before(_eq)`, plus one subtraction (`next - now`) that runs only when
  `time_after(next, now)` holds. `jiffies_to_msecs` of a delta of at most about 130 s fits in
  `unsigned int`.
- **Harness:** the bounded `addf` and `vsnprintf` buffers, and ASan/UBSan, are clean on both
  platforms.

### 2. Concurrency & Thread Safety

No issues found. I traced these in the 7.3 tree:

- **Requeue during cancel:** `cancel_delayed_work_sync` → `__cancel_work_sync(…,
  WORK_CANCEL_DISABLE)` disables the work while it waits. A requeue from inside the running
  retry, through `_queue` → `queue_delayed_work`, fails, so the state stays PENDING and `_stop`
  returns "down".
- **`probe_retry_next`:** only the work and `_resume` write it. `_resume` runs only after
  `.suspend`, `.freeze` or `.poweroff` has cancelled the work, and the freezable workqueue is
  frozen. So the field has a single writer at any time.
- **Wakeup calls:**
  - `device_wakeup_disable` runs in probe and `device_wakeup_enable` in the work, both in
    process context. Their internal `dev->power.lock` and the SRCU make them safe against
    sysfs.
  - `device_wakeup_enable`'s "Suspicious … during system transition" `dev_dbg` can't fire,
    because the work is freezable.
- **Hibernation image write:** while the image is written, the work that `.thaw` queued can
  only reach the frozen queue's inactive list, and `.poweroff`'s cancel takes it from there.
  If the image write fails, the time it took counts toward the 120 s. That is a harmless
  corner, not a finding.

### 3. Resource Management

No issues found.

- **Wakeup source:** `device_wakeup_disable` unregisters it. `device_wakeup_enable` registers a
  new one and re-attaches `dev->power.wakeirq` through `device_wakeup_attach`.
- **Every state:** `i2c_device_remove` and the probe error path both call
  `dev_pm_clear_wake_irq` and `device_init_wakeup(false)`, so nothing leaks.
- **IRQs, hid and buffers:** unchanged since R1. The harness checks their balance in all four
  states for every teardown, including `bad=` (no misuse) in every snapshot.

### 4. Error Handling & System Boundaries

No new issues found.

- The work ignores `device_wakeup_enable`'s return value. -EEXIST, if userspace already
  enabled it, is benign. -ENOMEM leaves wakeup off, which is the safe direction.
- A retry that fails with an error that isn't retried gives up with `dev_warn`, as before.

### 5. Input Validation & Security

**R2-01** (Minor; listed under 6). Nothing else: the round adds no new trust boundary, network
access or dependency. The harness is test-only and uses the host's C compiler.

### 6. Semantic Correctness

R2-01. Checked and correct:

- **Schedule:**
  - The first retry is at start + 5 s.
  - Each next one is due 5 s after the previous one started, or at once (clamped to `now`) if
    that one ran longer.
  - A retry is queued only if its due time is no later than start + 120 s.
  - So retries are at least 5 s apart and there are at most 24 in [5 s, 120 s], as the header,
    the doc, patches/ubuntu/README and TODO now say.
- **Drift:** with real queueing latency δ per retry, the schedule drifts by δ per retry
  because it anchors on the actual start. With 2 s attempts the 24th retry can be lost (23
  instead of 24). The docs say "at most 24", so they stay accurate. This is context, not a
  finding.
- **Wrap:** `time_before_eq(next, start + timeout)` and `time_after(next, now)` are wrap-safe.
  The harness's wrap scenario starts 30 s before the wrap, so the wrap falls inside the window.
- **Resume:** it queues the rest of the wait (`probe_retry_next - now`), or 0 if that has
  passed. Jiffies follow CLOCK_MONOTONIC, which excludes S3 and s2idle, and after a restore
  the image's jiffies are used. So "jiffies don't count the time asleep" is accurate.
- **Wakeup:** `probe_retry_wakeup = device_may_wakeup(dev)` is recorded before the disable, and
  re-enabled only at UP. GAVE_UP stays off, the same end state as stock's failed probe.
- **R1-02 wording:** the header and the doc now say accurately that a RESET goes out only after
  an earlier attempt (including the first probe) read a valid descriptor, and that in the
  usual failure no RESET is sent. "Starts at the address check" is accurate: ACPI's
  `power_up` is NULL, so the retry's first I2C transfer is the address check.

#### R2-01 (Minor): writing to `power/wakeup` while a retry is pending undoes R1-04's fix in both directions

- **Where:** 0002, `i2c_hid_probe_retry_start` (`device_wakeup_disable`) and
  `i2c_hid_probe_retry_work` (`if (ihid->probe_retry_wakeup) device_wakeup_enable(dev);`).
- **Requirement:** the contract says a device that never came up must be in a correct state.
  R1-04's fix is the stock-like end state of "no wake IRQ armed with no handler", and the doc
  calls this "wakeup disabled".
- **Why userspace can still change it:**
  - Stock's failed probe leaves the device **not wakeup-capable**: `i2c_device_probe`'s error
    path calls `device_init_wakeup(false)`, which removes `power/wakeup`.
  - 0002 leaves the device capable with wakeup disabled, so `power/wakeup` stays writable
    (`wakeup_store` → `device_set_wakeup_enable`).
  - The deferral starts at boot, which is exactly when udev `bind` rules and boot-time units
    write `power/wakeup`. Writing `disabled` to i2c touchpads is a common fix for laptops that
    wake in a bag.
- **What goes wrong:**
  1. **`enabled` while PENDING:** `device_wakeup_enable` re-attaches the wake IRQ, so the next
     suspend arms `enable_irq_wake` on a line with no handler. That is R1-04's hazard. The
     resolution record admits this gap, but neither the doc nor the header mentions it.
  2. **`disabled` while PENDING:** the write is a no-op, because wakeup is already off. When a
     retry reaches UP, it calls `device_wakeup_enable` because wakeup was on at probe time.
     That silently overrides the user's setting, and the device can wake the machine against
     an explicit policy. Nothing records this case.
- **Evidence:**
  - I read `wakeup_store`, `device_wakeup_enable/disable` and `i2c_device_probe` in the 7.3
    tree.
  - I ran the real extracted code in the harness (probe program, macOS):
    - Disable written while PENDING, then a retry succeeds: `state=UP … wake=on`.
    - Enable written while PENDING, then `pm_suspend`: `state=PENDING irq=free … wake=on`, so
      wakeup is enabled on a device with no IRQ.
  - Not reproduced on hardware.
- **Suggested fix (small, matches stock more closely):**
  - While deferred, make the device not wakeup-capable, as stock's failed probe does. In
    `_start`, call `device_wakeup_disable(dev)` and then `device_set_wakeup_capable(dev,
    false)`. Both are no-ops for a device that isn't capable, so `probe_retry_wakeup` should
    also record `device_can_wakeup(dev)`.
  - At UP, call `device_set_wakeup_capable(dev, true)` and then `device_wakeup_enable(dev)` if
    it was enabled.
  - `power/wakeup` then disappears while deferred, and writes can't race the retry. Remove
    needs nothing new, because `device_init_wakeup(false)` handles a device that isn't
    capable.
  - Add harness cases for both directions. The fake `struct device` needs a sysfs-write helper
    that refuses when `!can_wakeup`.
  - If this is judged not worth the code, at least record both directions in
    `docs/i2c-hid-probe-retry.md`.

### 7. Architecture & Design

No issues found.

- The schedule needs one more field (`probe_retry_next`) and keeps one queue helper, which
  serves both the work and resume. That is the smallest way to give resume "the rest of the
  wait".
- The harness design is sound:
  - It extracts the real patched blocks by their first line, so a patch reshape fails loudly
    ("extract: 0 of …").
  - It fakes only the kernel API and the stock functions underneath.
  - It pins the faked stock functions in `t-patch.sh`, apart from R2-02.

### 8. Test Quality

R2-02 and R2-03, both Nit. Otherwise strong:

- **It tests the code that ships:** 0002 is applied to the fixture with `apply_patch` (no
  fuzz, forward only), and 24 functions plus the types and DMI table are extracted from that
  file, so it tests whatever the patch says now.
- **Every check is accounted for:** the `DONE` count must equal the number of CHECK lines read,
  "runs to the end" requires exit 0, and any non-CHECK stdout fails.
- **Its fakes are faithful or stricter:**
  - `queue_delayed_work` returns false when the work is already queued and keeps the original
    due time, as the kernel does.
  - `run_work` clears pending before calling the function, so a self-requeue works.
  - `device_wakeup_enable` returns -EINVAL when the device isn't capable and -EEXIST when it is
    already enabled. `device_wakeup_disable` is a no-op when the device isn't capable. Both
    match `wakeup.c` in 7.3.
  - `free_irq`, `enable_irq` and `request_threaded_irq` misuse becomes `bad`, as the kernel
    WARNs. `disable_irq` on a freed IRQ is also flagged, which is stricter than the kernel and
    so can't hide a bug.
  - `hid_add_device` failure leaves the hid not ADDED, as a parse failure in 7.3 does.
  - DMI matching is a substring match, as `dmi_matches` does it.
  - The fake errno values are Linux's, not the host's.
- **Accepted limit:** the harness is single-threaded, so it can't show `cancel_delayed_work_sync`
  waiting for a running retry. Section 2 covers that by inspection. A test can't reasonably
  close this.
- **Both sides of the contract:** stock failures (non-P16, followers, other errors) and
  successful retries are asserted, as well as the forbidden misuse.
- **t-patch.sh pins:** the 8 pinned blocks (xfer, read_register, set_power, alloc/free buffers,
  lookup_quirk, the panel follower's register, and the dev_pm_ops table) are compared before
  and after the patch, with a count guard. This replaces the line greps R1-01 criticised. What
  remains is a change detector, and the resolution says so.

#### R2-02 (Nit): two faked stock functions are not pinned

- **Where:** `tests/i2c-hid-retry/driver.h:84` (`i2c_hid_irq`) and `:90`
  (`ihid_core_panel_follower_work`), against `tests/t-patch.sh` `stock()`.
- **What happens:**
  - The harness replaces both functions with no-ops, and neither is extracted or pinned.
  - A later 0002 revision that edits `i2c_hid_irq`, for example to drop IRQs while PENDING,
    would pass both the harness and `t-patch.sh`.
  - `driver.h`'s header says the stock functions it fakes are "the ones it must not change"
    and that `t-patch.sh` pins them. That is true of the list in the resolution record, but
    not of these two.
- **Evidence:** grep: neither name appears in `tests/t-patch.sh` or `tests/t-i2c-hid-retry.sh`.
- **Suggested fix:** add `'static irqreturn_t i2c_hid_irq('` and
  `'static void ihid_core_panel_follower_work('` to `stock()`, and change the block count to
  10.

#### R2-03 (Nit): the harness's failure messages swap "expected" and "actual" when the expected value is empty

- **Where:** `tests/t-i2c-hid-retry.sh`, `while IFS=$'\t' read -r tag name want got`.
- **What happens:**
  - Tab is an IFS whitespace character, so bash merges consecutive tabs.
  - For a check whose expected value is empty, the line `CHECK\tname\t\tACTUAL` reads as
    `want=ACTUAL`, `got=`.
  - Any mismatch still fails, so there is no false pass. But the message is inverted.
  - X14's real output, for instance:
    `FAIL retry: not a P16 (Dell Inc., XPS 13 9345): nothing queued / expected: [5000 ] /
    actual: []`. The test expected nothing queued and got `5000 `.
  - About 20 checks have an empty expected value (the "no retry", "nothing queued" and
    `log_find` checks).
- **Suggested fix:** use a non-whitespace separator, such as `\x1f` in `check()`'s printf with
  `IFS=$'\x1f'`, or wrap each field (`[%s]`) and strip the brackets in the script.

### 9. Code Organization

No issues found.

- **Function length:** `_probe_retry_work` is about 45 lines with the schedule comment. Its two
  halves (requeue, then the final state and log) read linearly, and splitting it would scatter
  the deadline logic.
- **Repo conventions:** the harness files keep the SPDX header, "n1x-kernel-ubuntu - …" and
  "Why:", and stay under 300 lines.
- **Leftovers:** there is no dead code. `system_wq` is unused, but it is kept on purpose for a
  mutant and marked `unused`.

## Severity Summary

- **Critical:** none.
- **Major:** none.
- **Minor:** R2-01 (0002, `i2c_hid_probe_retry_start` and `i2c_hid_probe_retry_work`):
  `power/wakeup` stays writable while a retry is pending. "enabled" re-arms a wake IRQ that has
  no handler, and "disabled" is overridden at UP.
- **Nit:**
  - R2-02 (`tests/i2c-hid-retry/driver.h:84,90`, `tests/t-patch.sh` `stock()`): the faked
    `i2c_hid_irq` and `ihid_core_panel_follower_work` are not pinned.
  - R2-03 (`tests/t-i2c-hid-retry.sh`, its read loop): an empty expected value swaps
    "expected" and "actual" in failure messages.

**New correctness or safety issues this round: none.** R2-01 is a semantic gap at the sysfs
boundary that the fixer partly acknowledged. Its impact depends on hardware wake capability,
which is unverified.

## Prior Finding Resolutions

| ID | Status | Evidence |
|---|---|---|
| R1-01 (Major) | **Fixed** | The harness runs the real patched code: it extracts from the fixture with 0002 applied (`TREE_MATCHES_FIXTURE_PLUS_0002`), 211 checks run in CI and locally, and it builds clean with gcc, clang and Apple clang. I re-ran M2, N5 and N13, and their failure counts match the record exactly (8, 28, 1). My six new behavioural mutants (X1, X3, X6, X9, X12, X13), plus X14, are all killed. The only survivor, X11, is equivalent in practice. Two small gaps remain, as R2-02 and R2-03. |
| R1-02 (Minor) | **Unresolved: awaiting the owner, as the brief states** | The code is unchanged (`if (!ihid->hid->version) return;`). The header ("A retry sends a HID RESET first only if an earlier attempt read a valid HID descriptor … while every descriptor fetch fails, as in the usual failure, no RESET is sent") and `docs/i2c-hid-probe-retry.md:61-64` describe the behaviour accurately. The doc's earlier error ("starts straight at the descriptor fetch") is corrected to "the address check", which is right because ACPI has no `power_up`. N17 (RESET before any descriptor) is killed. |
| R1-03 (Minor) | **Fixed** | Retries are now spaced from their start times (`attempt`, `probe_retry_next`), clamped to `now`, with the deadline on the due time. The harness checks 24 retries at 5…120 s (also across a jiffies wrap), 7 s and 9 s attempts, and suspend partway through a wait. X1 and X9 are killed. The log string is accurate as it stands (5 s between starts), and the docs explain it. |
| R1-04 (Minor) | **Fixed for the default path; the residual is tracked as R2-01** | `_start` disables wakeup and UP re-enables it. In 7.3, `device_wakeup_disable` unregisters the source, so `device_wakeup_arm_wake_irqs` doesn't arm it, and `device_wakeup_enable` re-attaches the wake IRQ. The harness covers wakeup enabled, disabled and not capable, and N5, N6, N7 and X3 are killed. The `power/wakeup` window is new finding R2-01. |
| R1-05 (Nit) | **Fixed** | The doc reads "`sys_vendor` containing `ASUS`, which on the P16 is exactly `ASUS`", and the header names both match strings. The harness checks that "ASUSTeK COMPUTER INC." matches. |
| R1-06 (Nit) | **Fixed** | The header and the doc both say shutdown skips `shutdown_tail` (i2c-hid-acpi's D3cold). The harness asserts `tail=0` for PENDING and GAVE_UP, and `tail=1` when the device is up. |
| R1-07 (Nit) | **Fixed** | The truncated `.ko.zst` and `.ko.xz` cases now hold the mark before the cut. A guard asserts that the decompressor "fails after the mark". I re-ran S2 and it is killed (`module: truncated .ko.zst` and `.ko.xz` fail). |

R1-02 is still open, by design, until the owner decides. R1's other findings are resolved.

## What's Done Well

- **The harness is the right answer to R1-01.** It runs the shipped patched code rather than
  greps, records misuse the way the kernel would WARN, and asserts exact state snapshots for
  every state × teardown. It fails loudly if a block can't be extracted or a check goes
  unreported. It also uses Linux errno values on macOS, which is the sort of detail that
  usually bites later.
- **The schedule fix is minimal and wrap-safe.** It has one field and one helper. Resume
  re-queues "the rest of the wait" for free, and the deadline is defined on the due time, so
  "none later than 120 s" holds by construction.
- **The wakeup fix uses the correct 7.3 APIs.** `device_wakeup_disable` unregisters the source,
  which is exactly what stops `device_wakeup_arm_wake_irqs`, and it records the prior state
  before disabling.
- **The resolution record is honest.** Its mutant counts reproduce exactly. It discloses the
  sysfs `enabled` gap and what it couldn't verify on hardware, and it states that the
  remaining `t-patch.sh` pins are change detectors.
