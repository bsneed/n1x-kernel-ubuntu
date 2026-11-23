# Keyboard and touchpad dead after a boot (patches/ubuntu/0002)

What `patches/ubuntu/0002` fixes on the ProArt P16, how it works, and how to read what it logs.
It is in kernel 7.3.0-n1x5. **Status:** built and tested off the hardware (it compiles with
`W=1` without warnings, and `tests/t-i2c-hid-retry.sh` runs the patched code against a fake
device: every state, error and teardown path below); not yet verified on the P16 itself.

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
- The devices are slow, not dead. Binding `i2c_hid_acpi` to them by hand 2-3 minutes later
  brought back the keyboard, the touchscreen and the touchpad; the ASUS device bound on a later
  try.
- I2C traces of the failures show the controller stalled mid-transfer (`INTR_STAT` 0, nothing
  received), and an immediate retry of a stalled command often works.
- The I2C domains are power-gated by NVIDIA's power-wrap driver over SCMI, not by ACPI. The
  firmware has no `_PS0`/`_PS3`/`_PR0`/`_RST` or reset GPIO for these devices. Don't use the
  power-wrap SCMI sysfs D3 hooks to power-cycle them: they wedge the SCMI mailbox.

## The fix

0002 changes `drivers/hid/i2c-hid/i2c-hid-core.c` (the code the ACPI glue `i2c-hid-acpi.c` calls).
On a machine in its DMI table, which holds only the P16 (`sys_vendor` exactly `ASUS`,
`product_name` containing `H7607BA`), a probe that fails with -ETIMEDOUT (-110) or -ENXIO (-6)
doesn't fail:

- What counts: the address check, the HID descriptor fetch, and the power-up, reset and report
  descriptor read that registering the HID device does. Any other error fails the probe as
  before. Other machines, and panel-follower touchscreens, behave exactly as stock.
- Probe returns 0, so the device stays bound to `i2c_hid_acpi`, but with nothing set up: its
  IRQ freed, the HID device not added, the device powered down, and its wakeup disabled (stock
  leaves a device whose probe failed with no wakeup either; with it enabled, its wake IRQ would
  be armed at every suspend with nothing to handle it).
- A delayed work (on the freezable system workqueue, so it never blocks probe or boot) then
  does what probe does: power up, a HID RESET, check the address, fetch the descriptor, request
  the IRQ, add the HID device. The first retry starts 5 s after the failure, and each next one
  5 s after the previous one started, or right after it if it took longer than that (a
  timed-out transfer takes 2 s). No retry starts later than 120 s after the failure, so there
  are at most 24. The RESET goes out only once an earlier attempt read a valid HID descriptor
  this boot, because the command register it is sent to comes from that descriptor; until then
  a retry starts straight at the address check.
- A retry that brings the device up enables its wakeup again, if it was enabled.
- Unbind/remove and shutdown cancel the work and wait for it. For a device that never came up
  they skip what assumes a working device (the sleep command, `free_irq()`). System suspend and
  hibernation stop the work the same way and start it again on resume, on the same schedule
  (the time asleep doesn't count).

## Its log lines

All three come from the device, so `journalctl -k -b | grep i2c_hid_acpi` shows them, e.g.
`i2c_hid_acpi i2c-3030443150435341:00: ...`. Before the first one, stock i2c-hid's
`failed to fetch HID descriptor: -110` and `Failed to fetch the HID Descriptor` still appear,
and each failed retry logs them again.

- `probe failed (-110), retrying every 5 s for up to 120 s` (info): the first probe failed with
  that error and the retries started ("every 5 s": between the starts of two retries).
  Without 0002 the device would now be dead until the next boot.
- `probe retry N succeeded, M ms after the probe failed` (info): retry N brought it up, M ms
  after that first failure. The keyboard or touchpad works from here.
- `giving up after N probe retries in M ms: -110` (warning): it never answered within the
  120 s, or a retry failed with an error that isn't retried (the error it ends with). M can be a
  little over 120000: the last retry may start at 120 s and then time out. The
  device stays bound with nothing set up. Rebinding it starts a new round of retries, e.g. for
  the touchpad:

  ```sh
  echo i2c-3030443150435341:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind
  echo i2c-3030443150435341:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind
  ```

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

- Verify on the P16: several cold boots and restarts with n1x5, watching for the log lines
  above and checking that the keyboard and touchpad come back without a rebind.
- Report it to linux-input.
