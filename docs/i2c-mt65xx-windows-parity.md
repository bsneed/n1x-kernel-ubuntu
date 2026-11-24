# i2c-mt65xx on the MT8901, driven like Windows drives it (patches/ubuntu/0003)

What `patches/ubuntu/0003` changes in the P16's I2C controller driver, why, and what is and
isn't known. It is in kernel 7.3.0-n1x6. **Status:** the same code, as an out-of-tree module on
7.3.0-n1x2, bound all four HID devices on the P16 and ran the stress below clean. As part of a
packaged kernel it is not validated over boots yet.

## What goes wrong

[i2c-hid-probe-retry.md](i2c-hid-probe-retry.md) describes the symptom: on some boots the
P16's keyboard, touchpad, touchscreen and hotkey device fail their probe or come up with a
broken report descriptor. That document says the devices are "slow, not dead". They aren't
slow. The fault is on the host side, in the SoC:

- **The controller hangs, not the device.** In a hung transfer SCL is held low by the
  controller's own pad (flipping the pad to GPIO input releases the line, 16 of 16 times). It is
  waiting on its APDMA channel.
- **DMA on one controller disturbs another.** With DMA transfers running on two of the
  NVDA0200 controllers at once, transfers hang, lose the tail of a read, or come back with
  bytes that the *other* controller's device sent.
- **`TRANSAC_COMP` can beat the DMA.** The controller raises it when the bus is done; the
  APDMA channel may not have written the last partial 16-byte chunk to memory yet. The driver
  unmaps the buffer and returns a read with a zeroed tail. hid then rejects the report
  descriptor ("unbalanced collection", "unknown main item").
- **No DMA, no failure.** Transfers of up to 16 bytes through the FIFO never failed. Neither
  did address-only (NACKed) transfers.
- **It is a state.** A boot is either clean (every transfer works, for hours) or bad; a bad
  state can also fade or appear within a boot. Nothing in the I2C or APDMA registers tells the
  two apart. What causes it is not known.

Windows on the same machine and BIOS never shows it, and its event log has no I2C or HID error.

## What Windows does differently

From the disassembly of `nvi2c.sys` (MediaTek's driver for the same IP):

| | Windows `nvi2c.sys` | Linux `i2c-mt65xx` (`mt8901_compat`) before 0003 |
|---|---|---|
| Controller and DMA reset | Before every transfer (DMA reset, soft reset, full register init) | At probe, at resume, after a timeout |
| Transfers of <= 16 bytes | FIFO, no DMA | DMA, always |
| Timeout, retry, bus recovery | None | 2 s timeout |
| Bus speed | 400 kHz from ACPI | 400 kHz from ACPI |

## What 0003 does

Three `mtk_i2c_compatible` fields, set only in `mt8901_compat`:

- `reinit_per_xfer`: `mtk_i2c_do_transfer()` calls `mtk_i2c_init_hw()` first.
- `fifo_depth = 16`: a transfer of at most 16 bytes in each direction goes through
  `mtk_i2c_do_transfer_fifo()`: DMA off in `CONTROL`, bytes written to and read from
  `DATA_PORT`. Every HID command and most input reports fit; report descriptors and long
  reports still use DMA.
- `dma_rx_done_wait`: after `TRANSAC_COMP` on a DMA read that wasn't NACKed, poll the RX
  channel for up to 20 ms (enable bit clear, or the RX bit of its `INT_FLAG` set). If it never
  finishes, the transfer times out (`-ETIMEDOUT`, controller reset) instead of returning a
  short buffer.

0002 stays: a transfer can still fail, and its probe retry is what picks that up.

## Evidence

On a P16 in the bad state, per ten 1342-byte report descriptor reads on i2c-4 while i2c-1 and
i2c-2 are hammered: the stock driver hung or truncated several; with the three changes, none
(and 1390 of 1390 8-byte transfers on i2c-1 OK, through the FIFO).

What didn't help, so isn't in the patch: a mutex across the controllers (worse), a reset after
the transfer without waiting for the DMA, a fixed delay after the read, DMA buffers below 4 GB,
and `RX_LEN` as the "done" test (it reads 0 either way).

## Not known

- What puts the SoC in the bad state, and how often a boot starts in it when nothing is
  stressing the bus. Earlier counts were taken with tests that themselves seem to make the
  next boot bad.
- Whether 0003 covers the first seconds of a bad boot as well as it covers the stress.
- Windows' PEP writes a `SuspendMode` flag to firmware that Linux's port doesn't. Untested.

## Checking a boot

```sh
sudo dmesg | grep -iE 'i2c-mt65xx|i2c_hid|unbalanced|unknown main'
for d in MKB0001 ASTH0001 3030443150435341 313030304B544C49; do
	ls /sys/bus/i2c/devices/i2c-$d:00/ | grep -c '^0018:'
done
```

Four `1`s and no timeout or descriptor lines is a clean boot.
