# Keyboard and touchpad dead after a boot (patches/ubuntu/0002)

What `patches/ubuntu/0002` fixes on the ProArt P16, how it works, and how to read what it logs.
It is in kernel 7.3.0-n1x5 and later. **Since 7.3.0-n1x7 it is the safety net, not the fix:**
the failures come from the SoC's I2C DMA, not from slow devices, and `patches/ubuntu/0003`
takes DMA out of the reads ([i2c-mt65xx-windows-parity.md](i2c-mt65xx-windows-parity.md)).
Where this document says the devices are "slow" or "answer late", read "the controller's DMA
hung or cut the transfer short"; 0002's header still has the old wording. 0002 stays for the
transfers that can still fail, and on n1x6 it did bring back a touchpad whose probe timed out.

**Status of 0002 itself:** built and tested off the hardware (it compiles with
`W=1` without warnings, and `tests/t-i2c-hid-retry.sh` runs the patched code against a fake
device: every state, error and teardown path below). On the P16 it works as designed, but its
first 120 s window was too short, and a device that sent a corrupted report descriptor counted
as up ([Tested on the P16](#tested-on-the-p16)). It now retries for 300 s and retries a
rejected report descriptor too; neither is verified there yet.

## The bug

On the ProArt P16 H7607BA (BIOS 300, touchpad firmware V1.26.0918.1, which Windows installed on
2026-11-22), the internal I2C HID devices sometimes don't come up at boot:

| Device | ACPI | HID | Bus |
|---|---|---|---|
| Internal keyboard | `\_SB.I2C2.TPD0`, `i2c-MKB0001` | 0B05:4B42 | i2c-2, 0x15 |
| Touchscreen | `\_SB.I2C2.TPL0`, `i2c-313030304B544C49` | 222A:5554 | i2c-2, 0x10 |
| ASUS HID device (hotkeys) | `\_SB.I2C1.ATHD`, `i2c-ASTH0001` | 0B05:4543 | i2c-1, 0x17 |
| Touchpad | `\_SB.I2C4.ETPD`, `i2c-3030443150435341` | 093A:4F01 | i2c-4, 0x15 |

The touchpad's address comes from firmware NVS (`ETPD._CRS`: `ADR1 = \_SB.TPDA`); on BIOS 300
it is 0x15.

On a bad boot, `i2c_hid_acpi` logs `failed to fetch HID descriptor: -110` (sometimes -6) for
some or all of them, after the `i2c-mt65xx` controller's 2 s timeout, and stock i2c-hid gives up
on the device for good: no keyboard or touchpad until the next boot.

What is known about it:

- It happens on cold boots and on warm restarts, on battery and on the charger. Nothing at
  shutdown causes it. (An earlier attempt,
  [PR #2](https://github.com/bsneed/n1x-kernel-ubuntu/pull/2), kept the devices awake at shutdown and loaded
  i2c-hid early from the initramfs; neither helped, and both are gone. #2 is superseded.)
- Binding `i2c_hid_acpi` to them by hand 2-3 minutes later brought back the keyboard, the
  touchscreen and the touchpad; the ASUS device bound on a later try. That read as "the devices
  are slow, not dead". It was wrong: the devices answer at once, and what fails is the
  controller's DMA, which hangs transfers for as long as the SoC is in a bad state
  ([i2c-mt65xx-windows-parity.md](i2c-mt65xx-windows-parity.md)).
- I2C traces of the failures show the controller stalled mid-transfer (`INTR_STAT` 0, nothing
  received), and an immediate retry of a stalled command often works.
- The I2C domains are power-gated by NVIDIA's power-wrap driver over SCMI, not by ACPI. The
  firmware has no `_PS0`/`_PS3`/`_PR0`/`_RST` or reset GPIO for these devices. Don't use the
  power-wrap SCMI sysfs D3 hooks to power-cycle them: they wedge the SCMI mailbox.

## The fix

0002 changes `drivers/hid/i2c-hid/i2c-hid-core.c` (the code the ACPI glue `i2c-hid-acpi.c` calls).
On a machine in its DMI table, which holds only the P16 (`sys_vendor` containing `ASUS`, which
on the P16 is exactly `ASUS`, and `product_name` containing `H7607BA`), a probe that fails with
-ETIMEDOUT (-110) or -ENXIO (-6) doesn't fail:

- What counts: the address check, the HID descriptor fetch, and the power-up, reset and report
  descriptor read that registering the HID device does. Any other error fails the probe as
  before. Other machines, and panel-follower touchscreens, behave exactly as stock.
- Probe returns 0, so the device stays bound to `i2c_hid_acpi`, but with nothing set up: its
  IRQ freed, the HID device not added, the device powered down, and its wakeup disabled (stock
  leaves a device whose probe failed with no wakeup either; with it enabled, its wake IRQ would
  be armed at every suspend with nothing to handle it).
- A delayed work (on the freezable system workqueue, so it never blocks probe or boot) then
  does what probe does: power up, a HID RESET (see below), check the address, fetch the
  descriptor, request the IRQ, add the HID device. The first retry starts 5 s after the
  failure, and each next one 5 s after the previous one started, or right after it if it took
  longer than that (a timed-out transfer takes 2 s). No retry starts later than 300 s
  (5 minutes) after the failure, so there are at most 60.
- The RESET goes out only once an earlier attempt read a valid HID descriptor, because the
  command register it is sent to comes from that descriptor. In the usual failure, where the
  descriptor fetch itself times out, no RESET is sent until a fetch has worked, and a retry
  starts straight at the address check; the ACPI tables give no other way to find the register.
- A retry that brings the device up enables its wakeup again, if it was enabled.
- A device can also answer before it is ready, with a report descriptor that is cut short or
  zeros. Stock `hid_add_device()` adds the HID device anyway: it doesn't parse the descriptor,
  the driver's probe does (`hid_open_report()`), and that probe's failure doesn't reach
  `hid_add_device()`. So the probe counts as a success and the device stays dead. On the P16,
  0002 therefore checks the descriptor in `i2c_hid_parse()`, right after reading it and before
  `hid_add_device()` keeps it: every item must fit and be a short item, and the collections
  must open and close in balance, with at least one. These are the structural checks of 7.3's
  `hid_parse_collections()`; "at least one collection" is stricter than it (an all-zero
  descriptor parses, but nothing can use it). If the check fails, the HID device is not added,
  the error is -EBADMSG (-74), which nothing else on that path returns, and it is retried like a
  timeout, within the same 300 s. A descriptor that passes is kept exactly as stock keeps it.
  Not checked: what `hid_open_report()` rejects in a well-formed descriptor (a report size over
  256 bits, an invalid report ID, a global stack under- or overflow, nested delimiters); such
  a device is added as before, and its driver's probe fails as before. The check runs on the
  descriptor as read, before any driver's `report_fixup()`. Of the fixups in 7.3, the only one
  for these four devices is hid-asus's `QUIRK_FIX_NOTEBOOK_REPORT` (keyboard and ASUS device),
  which changes one Logical Maximum in place, so no fixup could have made a rejected
  descriptor valid.
- Nothing else in registering the HID device is retried: `hid_add_device()`'s `-ENODEV` (the
  HID core ignores the device), and a failure of `device_add()`, fail the probe as before, and
  an error after the HID device was added (the QTEC re-power-on) is stock's.
- Unbind/remove and shutdown cancel the work and wait for it. For a device that never came up
  they skip what assumes a working device: the sleep command and `free_irq()`, and at shutdown
  also `shutdown_tail` (i2c-hid-acpi's D3cold), as stock never calls shutdown on a device whose
  probe failed. System suspend and hibernation stop the work the same way and start it again
  on resume, on the same schedule (the time asleep doesn't count).

## Its log lines

All of them come from the device, so `journalctl -k -b | grep i2c_hid_acpi` shows them, e.g.
`i2c_hid_acpi i2c-3030443150435341:00: ...`. Before the first one, stock i2c-hid's
`failed to fetch HID descriptor: -110` and `Failed to fetch the HID Descriptor` still appear,
and each failed retry logs them again.

- `probe failed (-110), retrying every 5 s for up to 300 s` (info): the first probe failed with
  that error and the retries started ("every 5 s": between the starts of two retries).
  Without 0002 the device would now be dead until the next boot.
- `probe retry N succeeded, M ms after the probe failed` (info): retry N brought it up, M ms
  after that first failure. The keyboard or touchpad works from here.
- `report descriptor rejected (unbalanced collection, N bytes)` (error): the report
  descriptor the device sent fails the check above (the reason is one of `long item`,
  `item past the end`, `end of a collection never opened`, `unbalanced collection`,
  `no collection`). Stock's `can't add hid device: -74` follows. On the first probe, the
  `probe failed (-74), ...` line then says the retries started; on a retry:
- `probe retry N read a bad report descriptor, retrying` (info): retry N was rejected that way
  and the next one is queued. Other failed retries log only stock's lines.
- `giving up after N probe retries in M ms: -110` (warning): it never answered within the
  300 s, or a retry failed with an error that isn't retried (the error it ends with). M can be a
  little over 300000: the last retry may start at 300 s and then time out.

## After a give-up

A device that gave up stays bound to `i2c_hid_acpi` with nothing set up (no HID device, no
IRQ). A plain `bind` of it fails with `-EBUSY`, because it is still bound. To try again by hand,
unbind it, then bind it: that runs probe again and, if it fails, a new round of retries. For
the touchpad:

```sh
echo i2c-3030443150435341:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind
echo i2c-3030443150435341:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind
```

`ls /sys/bus/i2c/drivers/i2c_hid_acpi/` lists the names of the others (`i2c-MKB0001:...`,
`i2c-ASTH0001:...`, `i2c-313030304B544C49:...`).

Making a plain `bind` work, by releasing the driver when the retries give up, is deferred: the
retry work can't call `device_release_driver()`, because that takes the device lock, which
remove holds while it waits for the work (`cancel_delayed_work_sync()`), so the two would
deadlock. Doing it safely needs a work item outside the driver's data, holding a reference to
the device, which is more machinery than one manual step is worth for now.

## Tested on the P16

On rtx24, with 0002 built as a module against kernel n1x2 and its first window of 120 s, the
retry worked as designed but gave up too soon. On a bad boot (about 1 in 5 restarts, on the
charger), the keyboard, the touchpad and the ASUS device all gave up at 118.6 s after 23 retries.
Then they answered on their own: the keyboard at about 140 s of uptime, the touchpad at 154 s
and the ASUS device at 166 s. The touchscreen (i2c-2, 0x10) bound at 5.2 s; it only stalls
behind the keyboard's hung transfer on the same bus. Earlier rebinds by hand at 3-5 minutes all
worked.

So 0002 now retries for 300 s, keeping the 5 s interval: well past the latest device seen
(166 s of uptime) and as long as the rebinds by hand that worked, while a device that is really
gone still gives up within 5 minutes.

With the 300 s window, on a bad boot, the retries brought up the keyboard (5.5 s), the
touchscreen (12.6 s) and the touchpad (20.8 s). But the ASUS device (ASTH0001, 0B05:4543)
"came up" at 7.1 s with a corrupted report descriptor: hid-generic logged
`unknown main item tag 0x0` ten times and `unbalanced collection at end of report
description`, then `probe with driver hid-generic failed with error -22`. The device was half
ready; i2c-hid counted it as up, because `hid_add_device()` returned 0, and its hotkeys stayed
dead with no further retry. Unbinding and binding it by hand then got -110, and the retry
brought it up cleanly 5.4 s after that. Hence the report descriptor check above.

## install.sh and check.sh

- `install.sh` (install and `--remove`), on the P16, deletes
  `/etc/dracut.conf.d/50-i2c-hid-early.conf` if PR #2's `install.sh` wrote it (its first line
  starts with `# Generated by n1x-kernel-ubuntu (scripts/install.sh)`), before it refreshes
  every initramfs. A file of that name written by hand stays, with a warning.
- `check.sh`, on the P16, reports whether the i2c-hid module (`.ko`, `.ko.zst` or `.ko.xz`) has
  0002, from the format string of its first log line, and whether the running module is that
  file (srcversion). An n1x3 or n1x4 module from PR #2 has the P16's DMI entry too, but not
  this string, so it doesn't count.

## Still to do

- Watch boots of 7.3.0-n1x7 on the P16 for the log lines above. With 0003 a retry should be
  rare; each one is a transfer that still failed and is worth a look.
- After a failed read, reset the device. On n1x6 a keyboard whose read was cut off stayed dead,
  bound and with its hid, until it was unbound and bound; no probe failed, so nothing retried.
- A plain `bind` after a give-up ([After a give-up](#after-a-give-up)), if the manual unbind
  turns out to be needed in practice.
- Report it to linux-input.
