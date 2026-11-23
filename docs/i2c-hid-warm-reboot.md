# Keyboard and touchpad dead after a restart (patches/ubuntu/0002)

What `patches/ubuntu/0002` and `install.sh`'s early i2c-hid load are for, and how they fared on
the ProArt P16. **Status: not fixed, and 0002's premise is wrong.** A cold boot fails the same
way a restart does (see [It is a probe race](#it-is-a-probe-race-not-shutdown-2026-11-22-evening)),
so nothing Linux does at shutdown causes it. The failure is intermittent on any boot; the next
step is timing the first touchpad transfer on good and bad boots.

## The bug

On 2026-11-22 Windows installed touchpad firmware V1.26.0918.1 on rtx24 (ProArt P16 H7607BA,
BIOS 300). Since then a **restart** from Linux leaves three I2C HID devices dead:

| Device | ACPI | HID | Bus |
|---|---|---|---|
| Internal keyboard | `\_SB.I2C2.TPD0`, `i2c-MKB0001` | 0B05:4B42 | i2c-2, 0x15 |
| Touchscreen | `\_SB.I2C2.TPL0`, `i2c-313030304B544C49` | 222A:5554 | i2c-2 |
| ASUS HID device (hotkeys) | `\_SB.I2C1.ATHD`, `i2c-ASTH0001` | 0B05:4543 | i2c-1, 0x17 |
| Touchpad | `\_SB.I2C4.ETPD`, `i2c-3030443150435341` | 093A:4F01 | i2c-4, 0x15 |

The touchpad's address comes from firmware NVS (`ETPD._CRS`: `ADR1 = \_SB.TPDA`); on BIOS 300
it is 0x15. (An earlier version of this table said 0x10; nothing answers there.) 0x33 on i2c-4
reads all zeros on healthy boots too and is a normal neighbour, probably the haptics chip.

They are dead in GRUB too (on the boots where GRUB was checked), and Linux logs
`i2c_hid_acpi ...: failed to fetch HID descriptor: -110` for each. Reloading `i2c_hid_acpi` from
the wedged state was believed not to help; see below for what does. Removing all power has
brought them back, though not every time:

> Unplug the charger, then hold the power button for 30-60 s. Power on.

(Booting Windows and restarting into Ubuntu also worked, and so, once, did simply restarting
again.)

## The cause, as far as tests go

Controlled restarts from 7.3.0-n1x2, with i2c-hid built by hand (rtx24
`/lib/modules/7.3.0-n1x2/updates/i2chid-test/`):

| i2c-hid | Probed | GRUB after the restart | Linux after the restart |
|---|---|---|---|
| stock | late (~3.3 s, from the root file system) | dead | dead |
| stock | early (~1.1-1.2 s, from the initramfs) | dead | dead |
| no SET_POWER(SLEEP) in `i2c_hid_core_shutdown()` | late | works | dead (gone before the probe) |
| no SET_POWER(SLEEP) in `i2c_hid_core_shutdown()` | early | works | works 3 times; dead once |

So the SET_POWER(SLEEP) that i2c-hid sends every device at shutdown wedges these controllers
across a warm reset, and even without it they stop answering a few seconds into the next boot
unless i2c-hid takes them over first.

Those test modules skipped the command for every I2C HID device. The first version of 0002
(7.3.0-n1x3) skipped it only for the keyboard, the ASUS device and the touchpad, matched by
HID ID. Its first restart (n1x3 restart 1 below) left all four dead, the touchscreen
included. i2c-hid came from the initramfs as intended (dracut applied the `rd.driver.pre`
options at 0.73 s), and still logged `failed to fetch HID descriptor` at 2.78 s, before the root
device was found at 3.39 s: -110 for the touchpad, ASTH0001 and the touchscreen, -6 for the
keyboard. n1x3 had still put the touchscreen, on the keyboard's bus, to sleep at shutdown. The
second version, below, spares them all:

- `patches/ubuntu/0002` adds `I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN` to `i2c-hid-core.c`, which
  skips that command in `i2c_hid_core_shutdown()`, and sets it for every I2C HID device on a
  machine in a DMI table holding only the P16 (`sys_vendor` ASUS, product `H7607BA`), as the
  test modules did. Suspend and remove still put them to sleep. Not upstream; still to be
  reported to linux-input.
- `install.sh`, on the P16 only, has the initramfs load `i2c_mt65xx i2c_hid i2c_hid_acpi` first:
  `/etc/dracut.conf.d/50-i2c-hid-early.conf` (`force_drivers`), or a marked block in
  `/etc/initramfs-tools/modules`. `--remove` deletes it.

`check.sh` (P16 only) reports both: that the installed and running `i2c-hid.ko` has 0002's
DMI entry, and, as root, that the running kernel's initramfs holds the three modules and
loads them first.

Any kernel without both, Ubuntu's included, wedges them on a restart. With both, a restart
still wedged them on the second try (below), so use Power Off on every kernel.

## Verification (2026-11-22)

Builds on spark1, each from a clean clone of `bsneed/i2c-hid-shutdown-quirk`, with
`scripts/container-build.sh` (ubuntu:26.04, about 20 minutes). Both logs show 0002 applied after
Omarchy's patches and 0001:

```
==> Applying 579 Omarchy patches
==> Applying patches/ubuntu
applied 0001-mt7925-fix-reset-panic-caused-by-the-wm2-rx-irq-mask.patch
applied 0002-hid-i2c-hid-no-sleep-on-shutdown-on-the-asus-proart-p16.patch
```

- 7.3.0-n1x3 at def8f3e: the first 0002 (three HID IDs).
- 7.3.0-n1x4 at b19ae97: the DMI version. The built `i2c-hid-core.c` has the DMI table, the
  quirk set after `i2c_hid_lookup_quirk()` and the test in `i2c_hid_core_shutdown()`, and
  `i2c-hid-core.o` holds the table's ident.

On rtx24:

- `install.sh` (from n1x2, then from n1x3) took over the hand-written
  `/etc/dracut.conf.d/50-i2c-hid-early.conf` (same `force_drivers`, now with our header; still
  the only file there), rebuilt every initramfs, and the second run left the drop-in as it
  was. The n1x3 and n1x4 initramfs hold the kernel's own `i2c-hid.ko`, `i2c-hid-acpi.ko` and
  `i2c-mt65xx.ko`, and `etc/cmdline.d/20-force_drivers.conf` has `rd.driver.pre=` for all three.
- On n1x3 and n1x4, `i2c_hid` was the in-tree module (`kernel/drivers/hid/i2c-hid/`, not
  `updates/`), and the running module's srcversion matched the file's. `sudo bash scripts/check.sh`:
  22 OK, 1 WARN (no USB4 device attached), 0 FAIL, both new lines OK. Its quirk check fails on
  n1x2's, n1x3's and Ubuntu 7.0.0-1026-nvidia's `i2c-hid.ko` (zstd) and on the n1x2 test module.

Boots, with Brandon checking the keyboard in GRUB (arrow keys) and at the login screen. Probe
times are when `hid-generic` bound the devices, or when i2c-hid gave up; every probe ran from
the initramfs (dracut applied `rd.driver.pre` at the time given):

| Boot | Kernel | Previous boot ended by | GRUB | Login | Kernel log |
|---|---|---|---|---|---|
| n1x3, first | n1x3 | restart from n1x2 (its test module) | OK | OK | dracut 0.73 s; all four devices bound at 1.12 s |
| n1x3, restart 1 | n1x3 | restart from n1x3 | not checked | dead | dracut 0.73 s; at 2.78 s -110 for the touchpad, ASTH0001 and the touchscreen, -6 for the keyboard |
| recovery | n1x3 | charger out, power held 30-60 s | | OK | |
| n1x4, first | n1x4 | Power Off from n1x3, power on | OK | OK | dracut 2.50 s; all four bound at 2.88 s |
| n1x4, restart 1 | n1x4 | restart from n1x4 | OK | OK | dracut 0.71 s; all four bound at 1.09 s |
| n1x4, restart 2 | n1x4 | restart from n1x4 | dead | dead | dracut 0.73 s; -110 for ASTH0001 and the touchpad at 2.78 s, for the touchscreen at 4.83 s; the keyboard's HID device bound only at 5.04 s |

The restart tests stopped there. With the earlier test modules (every device spared, probed
early) the restarts went 3 of 3 plus one where GRUB worked and Linux didn't. So skipping
SET_POWER(SLEEP) at shutdown and probing early is not a reliable fix. Since GRUB was dead after
n1x4's restart 2, whose shutdown sent no SET_POWER(SLEEP) to any I2C HID device, something else
at shutdown or across the reset wedges the controllers some of the time. Not tested yet: the
I2C controller's (`i2c_mt65xx`) state at shutdown, the reset path the firmware takes on a
restart, and what Windows sends at shutdown.

rtx24 was left wedged after n1x4's restart 2, for Brandon to recover with the long power hold.
GRUB's default is as `install.sh` set it, 7.0.0-1026-nvidia (no one-time boot pending), so that
is what the recovery boots; `--default` was not run. n1x1, n1x2 (with the test module), n1x3 and
n1x4 are installed, and so is our dracut drop-in.

## It is a probe race, not shutdown (2026-11-22, evening)

After n1x4, the default went back to 7.3.0-n1x2 with the hand-built test module and the early
load. Four restarts there were fine; the fifth wedged the keyboard and touchpad. The test module
and n1x4's 0002 are functionally identical (both skip SET_POWER(SLEEP) for every I2C HID device;
the test module only adds a `dev_info`), so the n1x2/n1x4 difference was noise.

Then a **cold boot** (hard power off, power on, 21:13) failed exactly like the restarts:
-110 for ASTH0001 and the touchpad at 2.78 s, for the touchscreen at 4.83 s. The restart that
followed (21:14) was fully healthy, the touchpad bound at 1.12 s. So the failure does not depend
on how the previous boot ended, and no shutdown-side change can fix it.

Probing the wedged state live (n1x2, 2026-11-22 21:06-21:12, rtx24):

- The keyboard was not wedged, only late: it NACKed (-6) at the 4.8 s probe, but a raw
  `i2ctransfer` minutes later returned a valid HID descriptor, and binding `i2c_hid_acpi` to
  `i2c-MKB0001:00` by hand brought it back. The touchscreen came back the same way. ASTH0001
  timed out on the first descriptor read of a manual bind and bound on the driver's retry.
- The touchpad stayed stuck: reads at 0x15 timed out (-110), i.e. it holds the bus. Unbinding
  and rebinding the `i2c-mt65xx` controller (`NVDA0200:04`) did not clear it.
- The I2C domains are power-gated by NVIDIA's power-wrap driver over SCMI, not by ACPI: binding
  the controller logs `mtk_pwrap_dev_probe: Device found at path \_SB_.I2C4, control type is
  scmi`. The firmware's ACPI has no `_PS0`/`_PS3`/`_PR0`/`_RST` or reset GPIO for these devices,
  and no `_PTS` or `_TTS` at all. Controller runtime PM is `unsupported`.

Working theory: the touchpad's firmware (and, more forgivingly, the others) needs settling time
after its I2C domain is powered, and i2c-hid sometimes reads it too soon; the touchpad then hangs
and does not recover, the others answer a later retry. Loading i2c-hid early narrows that window,
which would explain why early load and 0002 looked like they helped in small samples. The ACPI
path has no equivalent of i2c-hid-of's `post-power-on-delay-ms`.

Next: boot n1x2 several times with `trace_event=i2c:* tp_printk` on its command line and compare
the time from the I2C4 controller's power-up to the first touchpad transfer on good and bad boots.
If bad boots access it sooner, the fix is a per-device power-on delay in i2c-hid-acpi, plus a
reset and retry when the descriptor read times out, and 0002 and the early load can go.
