# Resolutions: i2c-hid probe retry, initial review (2026-11-23)

How each finding of [2026-11-23-i2c-hid-probe-retry-initial.md](2026-11-23-i2c-hid-probe-retry-initial.md)
(R1, of `e00a552`) was resolved on branch `bsneed/i2c-hid-probe-retry` (PR #3). Tests are in
`tests/t-*.sh` (`bash tests/run.sh`).

| ID | Severity | Resolution | Commit |
|---|---|---|---|
| R1-01 | Major | Fixed with a behavioural test. `tests/t-i2c-hid-retry.sh` applies 0002 to the fixture, extracts the patched types and functions from it (0002's own, probe with its error tail, remove, shutdown, the three pm callbacks, and the stock functions on their paths: address check, descriptor fetch, `__i2c_hid_core_probe`, init_irq, register_hid, power up/down, shutdown_tail, restore_sequence, encode_command), and builds `tests/i2c-hid-retry/harness.c` with the host's cc against fakes of the kernel API and of the device. Nothing needed was left unextracted; the stock functions it fakes instead (xfer, read_register, set_power, buffers, lookup_quirk, the panel follower's register, core suspend/resume) and the dev_pm_ops table are pinned unchanged in `t-patch.sh`, which drops its line greps. The scenarios and what they assert are listed below. It skips only without a C compiler (CI's ubuntu-24.04 has gcc); it ran with gcc 13 and clang 18 in ubuntu:24.04 and Apple clang 17 on macOS. All 13 of the review's mutants are killed, by the harness commit alone and on the final head, along with 19 more (table below). | d8ae393 |
| R1-02 | Minor | Not changed in code: an open contract deviation, for the owner to decide. The RESET is sent to the command register, which only a valid HID descriptor gives (the ACPI tables have no other source), so in the usual failure, a descriptor fetch that times out, no retry sends a RESET until a fetch has worked. The alternative, hard-coding a command register for each of the four P16 devices, is unverified and not done. The header and `docs/i2c-hid-probe-retry.md` now say this plainly, and that such a retry starts at the address check. Also stated in the PR description. | 04ce2b7 |
| R1-03 | Minor | Fixed. Each retry is queued for 5 s after the start of the one that just failed, or to run at once if that took longer, and only if that start is no later than 120 s after the failure (`probe_retry_next`; a resume queues what was left of the wait). With 2 s attempts that is 24 retries starting every 5 s, the last at 120 s; before, 17. The log line is now accurate as it was (5 s between starts), so it and check.sh's `I2C_HID_RETRY_MARK` are unchanged. Header, doc, patches/ubuntu/README and TODO describe the schedule. The harness's timing scenarios (2 s attempts, also with jiffies wrapping; 7 s and 9 s attempts; suspend mid-wait) fail on the old code (50 failures against e00a552's patch). | f6fc44a |
| R1-04 | Minor | Fixed. `i2c_hid_probe_retry_start()` records `device_may_wakeup()` and calls `device_wakeup_disable()`; a retry that reaches UP calls `device_wakeup_enable()` if it was enabled. In 7.3, `device_wakeup_disable()` unregisters the wakeup source, so `device_wakeup_arm_wake_irqs()` no longer arms it (and `dev_pm_arm_wake_irq()` checks `device_may_wakeup()` too); `device_wakeup_enable()` reattaches `dev->power.wakeirq` (`device_wakeup_attach`). `i2c_device_remove()` calls `dev_pm_clear_wake_irq()` and `device_init_wakeup(false)` in every state, so a GAVE_UP or PENDING device leaves nothing behind. The harness checks wakeup in every state, for a device with wakeup enabled, disabled, and not capable. Unverified on hardware: whether these GpioInts are wake-capable on the P16. One gap remains: a user who writes `enabled` to the deferred device's `power/wakeup` re-arms it until the retry ends. | 42d1ee2 |
| R1-05 | Nit | Fixed in the doc: `sys_vendor` containing `ASUS` (exactly `ASUS` on the P16); DMI_MATCH kept. The header names both match strings. | 04ce2b7 |
| R1-06 | Nit | Fixed: the header and the doc say shutdown of a device that never came up also skips `shutdown_tail` (i2c-hid-acpi's D3cold), as stock never calls shutdown on a device whose probe failed. The harness checks it (no tail in PENDING and GAVE_UP). | 04ce2b7 |
| R1-07 | Nit | Fixed. The truncated `.ko.zst` and `.ko.xz` modules hold the mark before the cut, with 256 kB that doesn't compress after it; the test first checks that the decompressor writes the mark and fails. The S2 mutant (only grep's status checked) now fails both. | 3a433a5 |

Found while doing this, not in the review: the doc said a retry without a descriptor "starts straight
at the descriptor fetch"; it starts at the address check (fixed in 04ce2b7).

## The harness (R1-01)

Each scenario starts a fake P16 (`sys_vendor` "ASUS", product "ProArt P16 H7607BA") whose
touchpad answers everything, then scripts results for the power-up, the address check, the
descriptor read (a failed read leaves garbage), the RESET, the IRQ request, hid add and SET_POWER.
A timed-out transfer advances jiffies by 2 s (7 s or 9 s in two scenarios); msleep advances them
too. A snapshot records the state, the IRQ (requested, enabled depth, requests, frees), hid adds
and destroys, power-ups and downs, wakeup, the work, the buffers, and every misuse a kernel would
WARN about or corrupt (freeing or enabling an IRQ that isn't requested, requesting it twice,
adding or destroying the hid twice, stock suspend/resume or SET_POWER on a device that isn't up,
the RESET without the command lock, queueing on another workqueue).

- **Stock paths:** non-P16 DMI (three machines and none), panel followers, and errors that are not
  retried (descriptor -EIO, HID 2.0 descriptor, power-up -EIO, IRQ -EBUSY, hid add -ENODEV, QTEC
  re-power-on after the hid was added) fail the probe as stock, torn down once.
- **Deferral:** -ETIMEDOUT and -ENXIO at the address check, descriptor fetch, power-up, IRQ
  request and hid add defer with nothing held, wakeup off, the first retry queued for 5 s and the
  "probe failed" line once; "ASUSTeK COMPUTER INC." matches too (DMI_MATCH).
- **Retries:** success at retry 1 or 2; an IRQ request that fails (no free); -EBUSY, -EIO and
  -ENODEV during a retry give up; a power-up timeout stops that retry; after a valid descriptor
  each retry RESETs to its command register (not the garbage of a later failed read), sleeps
  100 ms, and frees the IRQ when hid add fails; a failed RESET carries on; QTEC re-power-on
  after a retry's hid add is UP. The log lines are checked word for word, with retry counts and
  elapsed ms.
- **Timing:** 2 s attempts (also with jiffies wrapping during the retries): 24 retries at 5, 10, …,
  120 s, then "giving up after 24 probe retries in 122000 ms"; 7 s attempts back to back, none
  after 120 s; 9 s attempts, where the retry due at 118 s would start at 122 s and is not made.
- **Teardown in NONE, PENDING, UP and GAVE_UP:** remove, shutdown, suspend+resume and
  freeze+restore, each checking IRQ balance, hid destroy count, stock suspend/resume/SET_POWER/
  shutdown_tail/restore_sequence only when up, the work cancelled and requeued only while
  pending (for the rest of its wait), and no retry after remove or shutdown.
- **Wakeup:** enabled (off while deferred or given up, on again at UP), capable but disabled, not
  capable.

## Mutants

Each mutant replaces one `+` line of 0002 so that it still applies, and runs the whole suite
(`bash tests/run.sh` in ubuntu:24.04 with gcc). M1–M13 are the review's, on the final patch
(M7's line is now `ms = jiffies_to_msecs(now - …)`). All 13 were also killed against the harness
commit d8ae393 with e00a552's patch. M4 and N2 also leave an unused label or variable, so the
harness's warning check fails first; both fail behavioural checks as well (M4: the IRQ requested
twice; N2: the timing scenarios).

| Mutant | Change | Result on 04ce2b7 |
|---|---|---|
| M1 | `_stop` returns `state == PENDING` | killed, 10 failures |
| M2 | `_resume`: `case GAVE_UP` becomes `case NONE` | killed, 8 |
| M3 | the give-up branch stores UP | killed, 19 |
| M4 | the retry's register failure goes to `err_power_down` | killed, 4 |
| M5 | the retry's init_irq failure goes to `err_free_irq` | killed, 2 |
| M6 | `probe_retry_count++` removed | killed, 11 |
| M7 | `ms = jiffies_to_msecs(now)` | killed, 11 |
| M8 | the state is never written | killed, 42 |
| M9 | `if (!ret)` becomes `if (ret)` | killed, 58 |
| M10 | shutdown's `if (_stop)` inverted | killed, 8 |
| M11 | `msleep(100)` becomes `msleep(0)` | killed, 6 |
| M12 | `ret && !ADDED` becomes `ret \|\| !ADDED` | killed, 3 |
| M13 | a power-up error is ignored | killed, 7 |
| N1 | the queue ignores `probe_retry_next` (always 5 s) | killed, 14 |
| N2 | next retry 5 s after the attempt ends (the old cadence) | killed, 20 |
| N3 | `next` not moved up to now after a long attempt | killed, 3 |
| N4 | deadline `time_before` instead of `time_before_eq` | killed, 10 |
| N5 | wakeup not disabled when deferring | killed, 28 |
| N6 | wakeup not enabled again at UP | killed, 14 |
| N7 | wakeup enabled at UP even if it was off | killed, 3 |
| N8 | resume doesn't queue a pending retry | killed, 8 |
| N9 | probe defers a hid that was added | killed, 3 |
| N10 | the descriptor fetch returns the raw error on every machine | killed, 7 |
| N11 | retryable: -EIO instead of -ENXIO | killed, 41 |
| N12 | panel followers retried too | killed, 3 |
| N13 | the RESET goes to the current, possibly garbage, descriptor's register | killed, 1 |
| N14 | remove suspends a device that isn't up | killed, 4 |
| N15 | remove frees an IRQ that isn't requested | killed, 2 |
| N16 | restore's `if (_resume)` inverted | killed, 8 |
| N17 | RESET before any descriptor was read | killed, 15 |
| N18 | pm suspend's `if (_stop)` inverted | killed, 25 |
| N19 | the state is not set to PENDING on deferral | killed, 33 |
| S2 | `i2c_hid_has_retry` checks only grep's status (lib-i2c-hid.sh) | killed, 2 |

A definition the extractor can't find (an extra space after `static bool`) fails the suite with
"extract: 0 of static bool i2c_hid_probe_retry_stop(", so a patch reshaped that way can't pass
silently.

## Verification

- 0002 regenerated with `git format-patch` (first line `From <40-hex> `, `Drop it when`,
  Signed-off-by). It applies with `patch -Np1 --fuzz=0` to `tests/fixtures/linux-7.3` and, in
  the 7.3 tree after Omarchy (7.3-75) and 0001, to the fixture's `i2c-hid-core.c`; the result is
  identical to the edited source.
- `make W=1 M=drivers/hid/i2c-hid` (arm64, i2c-hid as modules): 0 compiler warnings pristine,
  0 patched, at each of f6fc44a, 42d1ee2 and 04ce2b7. `scripts/checkpatch.pl --strict`: 0 errors,
  0 warnings, 0 checks.
- On a `git archive` of each new commit, in ubuntu:24.04 (bash 5.2.21, shellcheck 0.9.0 as in CI,
  gcc 13): `bash -n` and `shellcheck` clean, `bash tests/run.sh` all passing with the harness run
  (`tests: 673 passed, 0 failed, 1 skipped` on 04ce2b7; the skip is `source_commit: no git`), and
  again with `CC=clang`. shellcheck 0.11.0 on macOS clean. `tests/t-i2c-hid-retry.sh` alone also
  passes under macOS's bash 3.2 and Apple clang. With no C compiler on PATH it reports
  `SKIP retry harness: no C compiler (cc, gcc or clang)`.
- Not verified: anything on the P16 (actual recovery, attempt durations, whether the devices'
  GpioInts are wake-capable). The CI debs run 45235312198 was built from e00a552, before these
  fixes.
