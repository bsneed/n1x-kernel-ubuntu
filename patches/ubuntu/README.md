# patches/ubuntu

Kernel patches this packaging needs on top of Omarchy's. `scripts/build.sh` applies every
`*.patch` here in name order after Omarchy's patches, with `patch -Np1 --fuzz=0`
(`apply_patch_dir` in `scripts/lib.sh`). A patch that is already in the tree fails the build.

| Patch | What | Drop when |
|---|---|---|
| `0001-mt7925-fix-reset-panic-caused-by-the-wm2-rx-irq-mask.patch` | Upstream c182bfe944eb (in 7.3.2 as 3c287de98388, CVE-2026-99560), unchanged. kernel.org 7.3 panics in `mt7925e_mac_reset()` on every MT7925 chip reset (NULL `napi_disable()`), which hung a ProArt P16 when its Wi-Fi reset after an MCU timeout while roaming. Omarchy carries no mt76 patches. Verified on the P16: [docs/mt7925-reset-panic.md](../../docs/mt7925-reset-panic.md). | The base is >= 7.3.2 |
| `0002-hid-i2c-hid-retry-a-failed-probe-on-the-asus-proart-p16.patch` | Ours, not upstream (still to be reported to linux-input). On the ProArt P16 H7607BA (DMI), i2c-hid retries a probe that fails with -ETIMEDOUT or -ENXIO, or reads a report descriptor that is cut short or garbage (checked before the HID device is added; -EBADMSG), in the background instead of giving up: retries start 5 s apart (back to back when one takes longer), none later than 300 s after the failure. It is the net under 0003: a transfer the controller's DMA hangs or cuts short can still fail a probe. After a give-up, unbind then bind the device to try again. [docs/i2c-hid-probe-retry.md](../../docs/i2c-hid-probe-retry.md). | Upstream retries such probes, or 0003's cause is fixed in firmware |
| `0003-i2c-mt65xx-drive-the-mt8901-like-the-windows-driver.patch` | Ours, not upstream (still to be reported to linux-i2c). For `mt8901_compat` only, i2c-mt65xx does what the vendor's Windows driver does: resets the controller and its DMA channel before every transfer, sends every read, and every transfer that sends up to 16 bytes, through the FIFO with no DMA, and waits for the RX DMA channel to finish before it hands back a read. On the P16 the SoC's I2C DMA sometimes hangs a transfer or cuts off the tail of a read, which is what leaves the keyboard, touchpad and hotkeys dead; 0002 stays as the net under it. [docs/i2c-mt65xx-windows-parity.md](../../docs/i2c-mt65xx-windows-parity.md). | Upstream does this for the MT8901, or firmware fixes the DMA fault |

What Ubuntu's user space needs is config, in `config/n1x.config`.

Name a patch `NNNN-short-description.patch`. Give it a git-format header that says why this
packaging carries it (and Omarchy doesn't), and a line starting `Drop it when` that says when it
can go; `tests/t-patch.sh` checks both. A backport keeps upstream's author, message and diff,
with the upstream and stable commits added at the top.
