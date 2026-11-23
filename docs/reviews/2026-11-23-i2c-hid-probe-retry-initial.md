# Review R1: i2c-hid probe retry on the ProArt P16 (PR #3), initial full review

## Summary

This change adds `patches/ubuntu/0002`, which retries a failed i2c-hid probe in the background
on the ProArt P16 H7607BA only. It also adds `scripts/lib-i2c-hid.sh`, which `install.sh` uses
to delete PR #2's early-load dracut drop-in and `check.sh` uses to report whether the running
i2c-hid has the retry. The rest is the n1x5 / NVIDIA n1x6 revision bump, docs and tests.

The kernel change looks correct on every path I traced:

- When probe defers, it returns 0 with the IRQ freed and the hid allocated but not added.
- Each IRQ request has exactly one free, the hid is destroyed exactly once, and the delayed
  work is cancelled synchronously before any teardown.
- System sleep is safe: the freezable workqueue is frozen before `.suspend` runs, and the
  sleep callbacks never touch a hid that was never added.
- Non-P16 machines, panel followers and other errors behave as stock.

It builds with W=1 without warnings, and checkpatch is clean.

The most important finding is about the tests, not the kernel code (R1-01). The 0002 checks in
`tests/t-patch.sh` match selected source lines. I applied 13 targeted behavioural mutants to
the patch, and 12 of them passed the whole suite. Among the survivors are an IRQ leak, a free
of an IRQ that was never requested, and a resume that skips every i2c-hid device on every
machine. The other findings are a contract deviation that needs the owner's sign-off (the HID
RESET can't precede retries until a descriptor has been read), the real retry cadence, a
wake-IRQ difference from stock, and three nits.

7 findings: 0 Critical, 1 Major, 3 Minor, 3 Nit.

## Scope and Evidence

- **Date / description:** 2026-11-23, R1 (full initial review) of loop run
  2026-11-23-i2c-hid-probe-retry, draft PR #3 (`bsneed/i2c-hid-probe-retry`).
- **Base:** `f44fc16ed106acb5f7fa93b1af53b32da81c9a33` (origin/main).
- **Head:** `e00a55250baabd8a2d7b1f456173317d4c980d96`. The range is `f44fc16..e00a552`.
- **Commits reviewed:**
  - `9fc97c7aec926f4eb859ab9965513c48597858dc`: Retry a failed i2c-hid probe on the ProArt
    P16 (patches/ubuntu/0002).
  - `a2ef511ef1e6481d01e9ba03e7cc4bc4358c7fe5`: On the P16, drop the old early i2c-hid load
    and check for 0002.
  - `e00a55250baabd8a2d7b1f456173317d4c980d96`: Raise the kernel to 7.3.0-n1x5 and the DKMS
    package to 620.73.04-n1x6.
- **PR head:** `gh pr view 3` reported headRefOid `e00a552…`, matching the snapshot, with
  isDraft true.
- **Uncommitted inputs:** none. `git status --porcelain --untracked-files=all` in
  `/Users/bsneed/work/n1x-kernel-ubuntu-review` (detached at e00a552) was empty before this
  report was written. This report is the only new file.
- **Contract:** the brief's D2–D8. The repo has no AGENTS.md or REVIEW.md, so I also used
  README.md, patches/ubuntu/README.md, the tests/ conventions, the earlier docs/reviews, and
  PR #2's branch (`bsneed/i2c-hid-shutdown-quirk`), which holds the text of the old drop-in.
- **Context limitations:**
  - I read project memory before forming findings: the loop's design summary, rtx24's rebind
    results, and the s2idle wake source on mt-eint GPIO 20. It held no prior review
    conclusions.
  - I did not use the PR description or commit messages as evidence.
- **Files read in full:**
  - the 0002 patch;
  - the stock 7.3 `i2c-hid-core.c` (the fixture) and `i2c-hid-acpi.c`;
  - `hid_add_device`, `hid_remove_device` and `hid_parse_report` (hid-core.c);
  - `i2c_device_probe` (i2c-core-base.c), `dev_pm_arm_wake_irq`, and mtk-eint's set_wake and
    suspend;
  - `scripts/lib-i2c-hid.sh`, the check.sh and install.sh diffs, `tests/t-patch.sh`,
    `tests/t-i2c-hid.sh` and `tests/run.sh`;
  - `docs/i2c-hid-probe-retry.md`, and the README, TODO, install.md, patches/ubuntu/README and
    sources diffs.

### Commands and results

- **Fixture fidelity:** in `w1-i2chid`, I copied the fixture, applied 0002 with `patch -p1`,
  and ran `cmp` against `/k/linux-7.3/drivers/hid/i2c-hid/i2c-hid-core.c`: `SAME_AS_TREE`. So
  the fixture is the tree's pre-0002 file, and the patch applies cleanly after Omarchy and
  0001.
- **Build:** in a `cp -a` copy (`/k/r1`), I ran
  `make -j2 W=1 drivers/hid/i2c-hid/i2c-hid-core.o`. It printed 0 warnings and returned 0.
  - The container's `.config` is not the Ubuntu-based build config, but it has
    `CONFIG_I2C_HID_CORE=m`, `PM_SLEEP=y` and `DMI=y`.
  - `strings` on the object shows the three log formats and the DMI ident.
  - `grep -acF 'retrying every %u s for up to %u s'` on the object gives 1.
- **checkpatch:** `scripts/checkpatch.pl --no-tree` on 0002 reported 0 errors and 0 warnings
  (327 lines).
- **Tests:** in `w1-lint` (bash 5.2.21, shellcheck 0.9.0), on a `git archive` of e00a552,
  `bash tests/run.sh` printed `469 passed, 0 failed, 1 skipped` (the skip is `source_commit: no
  git`).
- **Lint:** `bash -n` on every script and test was clean. `shellcheck -x scripts/*.sh tests/*.sh`
  exited 0.
- **CI:** `gh pr checks 3` shows lint passing in both runs and debs skipping (D8, out of scope).
- **Real build config:** I downloaded the pinned Ubuntu headers deb from Launchpad; its sha256
  matches `BASE_CONFIG_SHA256`. I extracted `.config`; its sha256 matches
  `BASE_CONFIG_FILE_SHA256`. It has:
  - `CONFIG_MODULE_SRCVERSION_ALL=y`, so `/sys/module/i2c_hid/srcversion` exists, which
    check.sh relies on;
  - `CONFIG_MODULE_COMPRESS_ZSTD=y`, so modules are `.ko.zst`, which is handled;
  - `CONFIG_I2C_HID_CORE=m`, so i2c-hid is not built in.

  `config/n1x.config` overrides none of these.
- **AI attribution:** a grep of the three commit bodies and the diff for
  claude/anthropic/co-authored/generated-with found nothing. The author is Brandon Sneed
  &lt;brandon@redf.net&gt;.
- **PR #2's drop-in:** `git show bsneed/i2c-hid-shutdown-quirk:scripts/lib-initramfs.sh`
  confirms that `early_dracut_text` wrote `# Generated by n1x-kernel-ubuntu (scripts/install.sh): …`
  as its first line. That matches the new `EARLY_MARK` prefix and the test fixture `ours()`.

### Probes and attacks (isolated copies only)

- **Kernel patch mutants** (`mut.sh`, run in `w1-lint` on copies of the archive): each mutant
  edits one `+` line of the 0002 patch, so the patch still applies, then runs the full suite.
  12 of 13 survived. Details are in R1-01.
- **Shell mutants** (`mut2.sh`):
  - Killed: S1 (install no longer drops the drop-in), S4 ("ours" matched anywhere in the file),
    S5 (no P16 gate), S6 (wrong mark).
  - Survived: S2 (the decompressor's exit status is ignored). I demonstrated an input that
    distinguishes it; see R1-07.
  - Survived: S3 (check.sh reads LOADED from the file instead of `/sys/module`). check.sh's call
    sites are untested, as the NVIDIA check's are, so I record this as context, not a finding.
- **Distinguishing input for S2:** a zstd module with the mark near the start, truncated to
  half. `zstd -t` fails, the original `i2c_hid_has_retry` returns 1, and the mutant returns 0.

### Not verified

- **No hardware behaviour:** I ran nothing on the P16 (rtx24). The Tailscale tool was denied
  to this reviewer. Unverified as a result:
  - actual recovery;
  - wake-IRQ arming (R1-04);
  - real attempt durations (R1-03).
- **No sparse or smatch** in the container. I didn't install either.
- **Full module not linked:** I didn't link or modpost-check the full `i2c-hid.ko`, because
  the tree has no `Module.symvers`. The new symbols are `dmi_check_system`,
  `system_freezable_wq`, `queue_delayed_work_on` and `cancel_delayed_work_sync`, all exported.

## Checklist Results

### 1. Panic & Crash Paths

No issues found. Scope checked:

- `i2c_hid_probe_retry_reset` writes 4 bytes into `cmdbuf`, which is at least
  HID_MIN_BUFFER_SIZE plus the command overhead.
- `ihid->hid` is non-NULL on every path that reaches the work or the stop/resume helpers,
  because probe only defers after `hid_allocate_device` succeeded.
- `container_of(to_delayed_work(work))` is correct.
- There is no unchecked indexing. The only narrowing is `jiffies_to_msecs` returning
  `unsigned int` for deltas of seconds.
- `ret` in the reset helper is always assigned, because the `scoped_guard` body always runs.
  W=1 gives no maybe-uninitialized warning.

### 2. Concurrency & Thread Safety

No defects found.

- **Ownership of `probe_retry_state`:** probe writes it before the first queue, and after that
  only the work writes it. Every reader that matters (`_stop`) reads it after
  `cancel_delayed_work_sync`. That function handles self-requeueing work, so a requeue racing a
  remove can't survive. The `smp_wmb`/`smp_rmb` pair copies the panel-follower pattern. It is
  redundant with the workqueue's own ordering, but harmless.
- **Remove versus a running retry:** remove holds the client's device lock and waits for the
  work. The work takes no client device lock. `hid_add_device` → `device_add` →
  `__device_attach` locks only the child, and the hid bus has no `need_parent_lock`. So there
  is no deadlock. Upstream's panel-follower work does the same `hid_add_device` from a work item
  that is cancelled under remove.
- **System sleep:**
  - `.suspend`, `.freeze` and `.poweroff` run after `freeze_kernel_threads()` has drained
    `system_freezable_wq`, so the work is never mid-attempt there, and cancel only removes a
    pending timer or inactive item.
  - `.resume`, `.thaw` and `.restore` requeue it while the queue is still frozen, and it runs
    after thaw.
  - Hibernation's image is taken after `.freeze` cancelled the work, and `.restore` requeues
    it.
- **Context (tradeoffs, not defects):**
  - A shutdown or unbind that lands during an attempt waits for it. That is about 4 s when the
    address probe times out. The worst case is about 26 s: parse's 4 hwreset tries, each with
    two 2 s SET_POWER timeouts plus `msleep(1000)`.
  - Suspend can't overlap an attempt, but freezing waits for the in-flight work. If one ever
    ran past `freeze_timeout_msecs` (20 s), that suspend would abort, which is safe.
  - After a retry's RESET, the device's reset-complete INT stays asserted until `enable_irq` in
    `register_hid`. The IRQ thread would normally consume it within the 60 ms `msleep` after
    PWR_ON, before `start_hwreset` sets `RESET_PENDING`. A stale-ack race is therefore
    unlikely. I record this as an observation, not a finding.

### 3. Resource Management

No issues found.

- **IRQ:** it is requested only in `i2c_hid_init_irq`, at probe or in a retry. Every failure
  after that point reaches `free_irq`, through probe's `err_free_irq` or the retry's
  `err_free_irq`. When the hid isn't added, `register_hid` has already called `disable_irq`. A
  deferred device holds no IRQ. Remove and shutdown skip `free_irq` exactly when the state is
  PENDING or GAVE_UP.
- **hid_device:**
  - It is allocated once in probe. On deferral it is neither destroyed nor added.
  - A retry adds it at most once: the loop stops at UP, so `hid_add_device`'s
    `WARN_ON(ADDED)` can't fire.
  - Remove destroys it exactly once, and `hid_remove_device` only calls `device_del` when
    ADDED.
  - Retrying `hid_add_device` after a failure is clean. `parse` fails before
    `hid_parse_report`'s `kmemdup`, so no `dev_rdesc` leaks, and errors after parse
    (`device_add`) are not retried.
- **Buffers:** they are kept on deferral (the retries need `cmdbuf`) and freed in remove. The
  devm `ihid` is freed only after remove's synchronous cancel.

### 4. Error Handling & System Boundaries

- R1-04 (Minor): see section 6.
- **Error-code gating (checked):** `i2c_hid_probe_retryable` is exactly
  `probe_retry && (-ETIMEDOUT || -ENXIO)`. The errors it can see come from:
  - `i2c_hid_probe_address`, which turns any SMBus error into -ENXIO as stock does, so every
    address-check failure is retried. That matches the contract and the docs.
  - the descriptor fetch, which returns the raw I2C error on the P16 and -ENODEV elsewhere;
  - `power_up`, which the ACPI glue doesn't use;
  - `hid_add_device` → `i2c_hid_parse`'s hwreset and report-descriptor read errors.
- **Descriptor fetch:** it returns the raw error only when that error is retryable on a P16.
  Every other error, and every other machine, still gets -ENODEV.
- **QTEC re-power:** the work treats "added, then re-power-on failed" as UP, where stock would
  destroy the hid. This is commented, and it doesn't apply to the P16's vendors (0B05, 222A,
  093A).

### 5. Input Validation & Security

Not applicable for the kernel side, which adds no new trust boundary. Shell side: no issues
found.

- `early_load_drop` deletes only a regular file, or a symlink to one, whose first line starts
  with PR #2's exact header, and only on the P16. Hand-written, empty, line-2-header and
  dangling-symlink files stay, with a warning. All of this is tested.
- `i2c_hid_has_retry` passes `--` before file names.
- There is no new network access, and no new subprocess beyond `zstd`, `xz` and `modinfo`.

### 6. Semantic Correctness

Findings: R1-02, R1-03, R1-04, R1-05 and R1-06.

Checked and fine:

- The DMI table has one entry (vendor "ASUS", product "H7607BA").
- Panel followers are excluded.
- Probe returns 0 on deferral.
- The deadline test uses `jiffies - start`, which is wrap-safe. The next attempt starts at most
  120 s after the failure.
- Attempts are counted as retries, excluding the initial probe.
- Success logs dev_info and giving up logs dev_warn, both with elapsed ms and the count.
- GAVE_UP leaves the device bound. The docs' unbind-then-bind recipe is right, because a plain
  bind would get -EBUSY.
- Non-P16 and other-error paths are behaviourally stock. Remove, shutdown and the PM callbacks
  return early only for non-NONE states, and NONE never changes.
- Suspend time doesn't count toward the 120 s, because jiffies stop in suspend and s2idle. The
  docs describe this as "the same deadline".
- check.sh tests the module file for the format string, and compares the running module with
  that file by srcversion. Both are valid under the real config.
- check.sh correctly fails PR #2's n1x4 module, which has the DMI ident but not the retry.
- check.sh reports WARN for a built-in i2c-hid. Under the real config it is not built in.
- D3: install.sh removes the drop-in before `update-initramfs`, in both install and
  `--remove`.
- D4: `N1X_REVISION=5` and `NVIDIA_N1X_REVISION=6`.
- D6: the docs keep the touchpad at 0x15 from `\_SB.TPDA` and the SCMI warning.

#### R1-02 (Minor): no HID RESET precedes the retries in the dominant failure

- **Where:** `patches/ubuntu/0002…patch`, `i2c_hid_probe_retry_reset` (`if (!ihid->hid->version) return;`).
- **Requirement:** D2: "sending a HID RESET before each retry".
- **What happens:** `hid->version` and `reset_cmd_reg` are set only after a descriptor has been
  read and validated. The bug as reported is a descriptor fetch that fails with -110 or -6
  before any descriptor has been read. In that case no retry sends a RESET until a fetch
  succeeds. The RESET only runs in the narrower case where the descriptor was read but
  registration (hwreset or report descriptor) timed out.
- **Why it isn't careless:** the limitation is forced. The command register comes from the
  descriptor, and the ACPI tables offer no alternative. The header and the docs state the
  limitation honestly.
- **Evidence:** code inspection. The test "only once a descriptor was valid" pins this
  behaviour.
- **Suggested resolution:** the owner accepts the narrowed requirement and records it in the
  PR. The only alternative is a hard-coded command register for each of the four P16 devices.
  I don't recommend it: it adds code and relies on an unverified register value.

#### R1-03 (Minor): "every 5 s" actually means 5 s after each failed attempt ends

- **Where:** `i2c_hid_probe_retry_work` and `i2c_hid_probe_retry_queue`, plus the log line
  `"probe failed (%d), retrying every %u s for up to %u s"` and the docs' "does what probe does
  every 5 s".
- **Requirement:** D2: "every 5 s for up to 120 s".
- **What happens:**
  - The work requeues itself with a 5 s delay after the attempt finishes.
  - On this bug, every failed attempt includes at least one 2 s i2c-mt65xx timeout. It
    includes two when the address probe times out, because `i2c_hid_probe_address` reads
    twice.
  - So the time from one attempt's start to the next is about 7–9 s, which gives about 12–16
    retries in 120 s rather than about 24.
  - The 120 s bound itself holds.
- **Evidence:** code inspection. The durations are estimates from the stated 2 s timeout, not
  measurements on hardware.
- **Suggested fix:** the simplest fix is to describe what the code does: "5 s apart", in the
  log string, the docs and patches/ubuntu/README. If the log string changes,
  `I2C_HID_RETRY_MARK` and its tests must follow. The alternative is to schedule against the
  attempt's start: record `t0 = jiffies` before the attempt, then queue with a delay of
  `max(0, interval - (jiffies - t0))`.

#### R1-04 (Minor, PLAUSIBLE): a deferred device keeps an armed wake IRQ that has no handler

- **Where:** 0002's probe deferral path, in its interaction with
  `drivers/i2c/i2c-core-base.c:i2c_device_probe` and `drivers/base/power/wakeirq.c:dev_pm_arm_wake_irq`.
- **Requirement:** D2: "no IRQ left requested on a device that never came up", which implies
  stock-like state for a device that never came up.
- **What happens:**
  1. With a wake-capable ACPI GpioInt, the i2c core sets `I2C_CLIENT_WAKE`, then calls
     `device_init_wakeup(true)` and `dev_pm_set_wake_irq(client->irq)` before the driver's
     probe runs.
  2. In stock, a failed `i2c_hid_acpi` probe leads the i2c core's error path to call
     `dev_pm_clear_wake_irq` and `device_init_wakeup(false)`.
  3. With 0002, probe returns 0, so a PENDING or GAVE_UP device stays wake-enabled.
  4. On every suspend, `dev_pm_arm_wake_irq` then calls `enable_irq_wake()` on an IRQ with no
     action. `irq_set_irq_wake` doesn't check for one.
  5. The P16's GPIO controller is mt-eint (project memory: wake IRQ 72 is mt-eint GPIO 20).
     `mtk_eint_irq_set_wake` sets `wake_mask` and unmasks the event, and `mtk_eint_do_suspend`
     writes `wake_mask` to the hardware mask whether or not the IRQ is requested.
  6. So a device holding its level-low INT asserted could wake the machine from s2idle, or keep
     waking it. Nothing reads the input register of a device with no handler. The INT can be
     asserted after the device's own power-on reset, after the retry's RESET, or because the
     device came alive after the driver gave up.
- **Evidence:** a code trace in the 7.3 tree. It is unverified on hardware: I don't know whether
  these GpioInts are `ExclusiveAndWake`. The current s2idle self-wakes come from the EC's
  GPIO 20 and are not caused by this.
- **How to check on the P16:**
  1. Run `cat /sys/bus/i2c/devices/<dev>/power/wakeup` for the four devices.
  2. If any reads `enabled`, unbind the touchpad's `i2c_hid_acpi` and rebind it while it is
     slow, or otherwise force GAVE_UP.
  3. Suspend, and see whether the wake IRQ is that device's pin.
- **Suggested fix, if wakeup is enabled there:**
  - In `i2c_hid_probe_retry_start`, save `device_may_wakeup(&client->dev)` and call
    `device_wakeup_disable()`.
  - Re-enable wakeup when a retry reaches UP.
  - Remove needs nothing, because the i2c core clears the wake IRQ on unbind.

  Otherwise, document this as a known difference from stock.

#### R1-05 (Nit): the docs say `sys_vendor` must be exactly ASUS, but the match is a substring

- **Where:** `docs/i2c-hid-probe-retry.md:52`, which says "`sys_vendor` exactly `ASUS`".
- **What happens:** `DMI_MATCH` uses `strstr`, so "ASUSTeK COMPUTER INC." would also match. With
  "H7607BA" required in `product_name` too, the practical effect is nil.
- **Suggested fix:** say "containing `ASUS`". Alternatively, use `DMI_EXACT_MATCH`, since the
  P16 reports exactly "ASUS". That is a behaviour change, so the owner should sign off on it.

#### R1-06 (Nit): the shutdown description leaves out the skipped `shutdown_tail`

- **Where:** the 0002 header ("skip the sleep command and free_irq()") and
  `docs/i2c-hid-probe-retry.md` ("skip what assumes a working device (the sleep command,
  `free_irq()`)").
- **What happens:** for a PENDING or GAVE_UP device, `i2c_hid_core_shutdown` returns before it
  calls `i2c_hid_core_shutdown_tail`. In i2c-hid-acpi that is
  `acpi_device_set_power(D3cold)`. Skipping it matches stock, which never calls shutdown for a
  device whose probe failed, and the P16 has no `_PS3`. The behaviour is fine; the description
  is incomplete.
- **Suggested fix:** add "and the ACPI D3cold of shutdown_tail, as stock never calls shutdown
  on a device whose probe failed".

### 7. Architecture & Design

No issues found.

- The change lives in i2c-hid-core, which owns the probe state machine. The ACPI glue has no
  probe-retry concept, and a retry there couldn't touch the IRQ or the hid lifecycle.
- The work reuses probe's own steps (`power_up`, `__i2c_hid_core_probe`, `init_irq`,
  `register_hid`) rather than duplicating them, so "what probe does" stays true.
- The patch correctly avoids `-EPROBE_DEFER`, which is unbounded and only re-triggers on other
  probes.
- The four-state enum is the minimum needed to tell "never deferred", "pending", "up" and "gave
  up" apart for remove, shutdown and PM.
- On the shell side, splitting out `lib-i2c-hid.sh` matches the repo's `lib-*.sh` pattern.
  Every file is under 300 lines, except the 1414-line kernel fixture, which is a verbatim
  upstream copy pinned by sha256.

### 8. Test Quality

R1-01 (Major) and R1-07 (Nit).

The shell tests for install.sh and check.sh are strong:

- The mutants that remove the install drop, widen what counts as "ours", drop the P16 gate or
  change the mark were all killed.
- The order of the drop relative to `update-initramfs` is pinned for both install and
  `--remove`.

#### R1-01 (Major): the 0002 checks in t-patch.sh miss most behavioural regressions of the patch

- **Where:** `tests/t-patch.sh:95-185`.
- **Requirement:** D7 asks for exhaustive tests of everything testable without hardware. The
  doc's status line also says the tests check the patched source.
- **What happens:** the checks grep selected lines or line ranges of the patched file. For
  example, they cover `_stop` only up to `cancel_delayed_work_sync`, only the PENDING case of
  `_resume`, and only the call order in `_probe_retry`. Code between or after the pinned
  ranges is free to change. In the table below, each mutant changes one `+` line of 0002. The
  patch still applies, and 12 of the 13 mutants leave the full suite passing
  (`469 passed, 0 failed`):

  | Mutant | Effect on a real kernel | Suite |
  |---|---|---|
  | M1: `_stop` returns `state == PENDING` instead of `!= UP` | remove on a GAVE_UP device calls `i2c_hid_core_suspend` on an unadded hid, and `free_irq` on an IRQ that was never requested (WARN "Trying to free already-free IRQ") | passes |
  | M2: `case GAVE_UP:` becomes `case NONE:` in `_resume` | **every i2c-hid device on every machine** skips resume and restore (state NONE returns true); GAVE_UP devices get `enable_irq` on a freed IRQ | passes |
  | M3: the GAVE_UP branch stores UP | same as M1, after a give-up | passes |
  | M4: the retry's register failure goes to `err_power_down` | the IRQ leaks every round, so the next `request_threaded_irq` gets -EBUSY and the retry gives up | passes |
  | M5: the retry's `init_irq` failure goes to `err_free_irq` | `free_irq` on an IRQ that was never requested | passes |
  | M6: `probe_retry_count++` removed | the logs always say 0 retries | passes |
  | M7: `ms = jiffies_to_msecs(jiffies)` | wrong elapsed time, so it gives up after the first retry | passes |
  | M8: the state is never written | an UP device is treated as down at remove (no `free_irq`, no suspend) | passes |
  | M9: `if (!ret)` becomes `if (ret)` | a success is logged as giving up and stored as GAVE_UP | passes |
  | M11: `msleep(100)` becomes `msleep(0)` | no settle time after the RESET | passes |
  | M12: `ret && !ADDED` becomes `ret \|\| !ADDED` | every successful retry is torn down (`free_irq` and power-down with the hid added) | passes |
  | M13: a `power_up` error is ignored | the attempt carries on as if `power_up` had succeeded | passes |
  | M10: shutdown's `if (_stop)` inverted | | **killed** |

- **Evidence:** `mut.sh` in `w1-lint`. Every mutant reported `subs=1`, so the edit was applied,
  and the "0002 applies" test passed, so the patch still applied.
- **Suggested fix:** the state machine is testable without hardware.
  - Extract the new functions from the patched file (the `fn` helper already does this) and
    compile them with `cc` in a small C harness. CI's ubuntu runner has gcc.
  - Stub `power_up`, `power_down`, `__i2c_hid_core_probe`, `init_irq`, `register_hid`,
    `free_irq`, `queue_delayed_work`, `cancel_delayed_work_sync` and `jiffies`.
  - Assert that IRQ requests and frees balance, the hid add and destroy counts, the state, the
    retry count and the deadline.
  - Cover these sequences: fail then succeed; fail until the deadline; a non-retryable error
    during a retry; remove, shutdown and suspend/resume in each of PENDING, UP and GAVE_UP; and
    the NONE state's stock path.

  If a harness is judged too heavy, the minimum is to pin each new function's full text, as the
  test already does for the "unchanged" bodies of parse and register_hid. Any edit would then
  force a deliberate test update. That is a change detector, not a behaviour test, and the
  resolution should say which one it chose.

#### R1-07 (Nit): the truncated `.ko.zst` test passes for the wrong reason

- **Where:** `tests/t-i2c-hid.sh:129-130`.
- **What happens:** the test truncates with `head -c 40`, and the result decompresses to no mark
  at all. `grep` therefore fails whether or not `i2c_hid_has_retry` checks the decompressor's
  exit status, so the S2 mutant (`[[ ${st[1]} -eq 0 ]]`) survives.
- **Evidence:** I made a zstd module with the mark at the start plus 200 kB of random data, and
  truncated it to half. `zstd -t` fails with "premature end", the original returns 1, and the
  mutant returns 0.
- **Suggested fix:** build the truncated case this way, with the mark before the cut. Do the
  same for `.ko.xz`.

### 9. Code Organization

No issues found.

- The new code sits in one block before `i2c_hid_core_probe`, and its names follow the file's
  `i2c_hid_*` convention.
- The longest new function, `_probe_retry_work`, is about 35 lines.
- There is no dead code and no TODO.
- The header has a "Drop it when …" line, the Signed-off-by, and the evidence.

## Severity Summary

- **Critical:** none.
- **Major:** R1-01 (`tests/t-patch.sh:95-185`): 12 of 13 behavioural mutants of 0002 pass the
  suite.
- **Minor:**
  - R1-02 (0002, `i2c_hid_probe_retry_reset`): no RESET precedes the retries until a
    descriptor has been read. D2 needs the owner's sign-off on this.
  - R1-03 (0002, `i2c_hid_probe_retry_work` and `_queue`, plus the docs): retries start 5 s
    after each attempt ends, so about 7–9 s apart.
  - R1-04 (0002's deferral path; PLAUSIBLE): a deferred device keeps an armed wake IRQ with no
    handler.
- **Nit:**
  - R1-05 (`docs/i2c-hid-probe-retry.md:52`): "exactly ASUS" is a substring match.
  - R1-06 (the 0002 header and the docs): the shutdown description leaves out the skipped
    `shutdown_tail`.
  - R1-07 (`tests/t-i2c-hid.sh:129-130`): the truncated `.zst` test passes for the wrong
    reason.

## Prior Finding Resolutions

Not applicable: this is R1.

## Context Notes (not findings)

- PR #2's install.sh also wrote a marked block into `/etc/initramfs-tools/modules` on systems
  that use initramfs-tools. The new cleanup removes only the dracut file, as D3 specifies. On
  26.04, dracut conflicts with initramfs-tools, and rtx24 uses dracut, so nothing is expected
  to be left behind.
- A successful retry means the hid device was added. A HID driver probe on top of it
  (hid-multitouch, hid-asus) can still fail on its own, exactly as in stock.

## What's Done Well

- The error-code gating is narrow and in the right place. The descriptor fetch's return value
  changes only for errors that are retryable on a P16, so every other machine keeps `-ENODEV`.
- `reset_cmd_reg` is copied only from a validated descriptor. A later failed fetch that partly
  overwrites `hdesc` can't redirect the RESET.
- The "added, then error" case (QTEC) is kept separate from "not added" in both probe and the
  retry, so the hid can never be destroyed twice or added again.
- The state machine is complete across every teardown path: remove, shutdown, freeze, thaw,
  poweroff and restore. Using the freezable workqueue makes the suspend interaction much
  simpler than it would otherwise be.
- The header is candid about the RESET limitation. The docs tell users how to read every log
  line and how to rebind a device.
- The shell side is carefully tested:
  - the header match looks at the first line only;
  - symlinks, empty files and directories are covered;
  - the decompression pipeline avoids the `grep -q` SIGPIPE trap;
  - comparing srcversions catches a stale copy in the initramfs.
