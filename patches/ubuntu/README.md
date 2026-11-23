# patches/ubuntu

Kernel patches this packaging needs on top of Omarchy's. `scripts/build.sh` applies every
`*.patch` here in name order after Omarchy's patches, with `patch -Np1 --fuzz=0`
(`apply_patch_dir` in `scripts/lib.sh`). A patch that is already in the tree fails the build.

| Patch | What | Drop when |
|---|---|---|
| `0001-mt7925-fix-reset-panic-caused-by-the-wm2-rx-irq-mask.patch` | Upstream c182bfe944eb (in 7.3.2 as 3c287de98388, CVE-2026-99560), unchanged. kernel.org 7.3 panics in `mt7925e_mac_reset()` on every MT7925 chip reset (NULL `napi_disable()`), which hung a ProArt P16 when its Wi-Fi reset after an MCU timeout while roaming. Omarchy carries no mt76 patches. Verified on the P16: [docs/mt7925-reset-panic.md](../../docs/mt7925-reset-panic.md). | The base is >= 7.3.2 |
| `0002-hid-i2c-hid-no-sleep-on-shutdown-on-the-asus-proart-p16.patch` | Ours, not upstream (still to be reported to linux-input). Adds `I2C_HID_QUIRK_NO_SLEEP_ON_SHUTDOWN` and sets it for every I2C HID device on a machine in a DMI table holding only the ProArt P16 H7607BA: since touchpad firmware V1.26.0918.1, a restart after `i2c_hid_core_shutdown()`'s SET_POWER(SLEEP) leaves its keyboard, ASUS HID device and touchpad dead, in GRUB too, until the laptop loses all power. Sparing only those three (the first version, n1x3) was not enough. It takes this and the early i2c-hid load `install.sh` sets up; the test matrix is in the patch and in [docs/i2c-hid-warm-reboot.md](../../docs/i2c-hid-warm-reboot.md). Omarchy carries no i2c-hid-core.c changes. | Upstream has an equivalent fix, or ASUS firmware no longer wedges |

What Ubuntu's user space needs is config, in `config/n1x.config`.

Name a patch `NNNN-short-description.patch`. Give it a git-format header that says why this
packaging carries it (and Omarchy doesn't), and a line starting `Drop it when` that says when it
can go; `tests/t-patch.sh` checks both. A backport keeps upstream's author, message and diff,
with the upstream and stable commits added at the top.
