# MT7925 reset panic (patches/ubuntu/0001)

What `patches/ubuntu/0001` fixes, and how it was verified on the ProArt P16.

## The bug

On 2026-11-21, rtx24 (ProArt P16 H7607BA, MT7925 14c3:7925, `mt7925e`, 7.3.0-n1x1) hung while
roaming between access points. An MCU message timeout led to `mt7925_mac_reset_work`, then a
NULL pointer dereference at 0xae0 in `mutex_lock` <- `napi_disable` <- `mt7925e_mac_reset`.

The cause is a regression new in 7.3, c4edf9e3e0e5 ("wifi: mt76: mt7925: replace shared rx irq
masks with per-chip definitions"). `mt7925_irq_map` sets `wm2_complete_mask`, but the MT7925
DMA layout has no `MT_RXQ_MCU_WA` queue, so that queue's NAPI is never set up.
`mt7925e_mac_reset()` disables it whenever the mask is set (`pci_mac.c`, `if
(irq_map->rx.wm2_complete_mask) napi_disable(...)`), so every chip reset panics, however it
was triggered.

Upstream fixed it in c182bfe944eb ("wifi: mt76: mt7925: fix reset panic caused by the WM2 rx
irq mask", 7.4-rc1), backported to 7.3.2 as 3c287de98388; it is CVE-2026-99560. None of
Omarchy's 7.3-75 patches touch mt76. 0001 is the upstream commit, unchanged, and it goes once
`KERNEL_VERSION` is 7.3.2 or newer (see TODO.md).

## Verification (2026-11-21)

Build: a clean clone of `bsneed/mt7925-wm2-fix` at 61f174a, built on spark1 with
`scripts/container-build.sh` (ubuntu:26.04, about 21 minutes). The log shows the patch applied
after Omarchy's:

```
==> Applying 579 Omarchy patches
==> Applying patches/ubuntu
applied 0001-mt7925-fix-reset-panic-caused-by-the-wm2-rx-irq-mask.patch
```

In the built tree, `mt7925_irq_map` has no `wm2_complete_mask`, and `MT7925_INT_RX_DONE_ALL`
is `MT7925_INT_RX_DONE_DATA | MT7925_INT_RX_DONE_WM`. The MT7927 and MT7928 maps keep theirs.

On rtx24:
- `install.sh` upgraded the n1x1 install: it added 7.3.0-n1x2 next to n1x1, installed DKMS
  620.73.04-n1x3 and built it for every kernel, and left the nvidia-persistenced override
  byte-identical.
- The rebooted kernel was 7.3.0-n1x2, with the n1x2 `mt7925e` loaded (srcversion
  B4515770DAD1394989FDA93; n1x1's is 81378FA611ADF9BE90A47DD).
- Three forced chip resets: `echo 1 > /sys/kernel/debug/ieee80211/phy0/mt76/chip_reset`
  (`mt792x_reset` -> `mt7925_mac_reset_work` -> `mt7925e_mac_reset`), 15 s apart, run
  detached. Each one reloaded the firmware, dropped the AP, reassociated (after one or two
  `denied association (code=30)` retries while the AP dropped the old association) and passed
  traffic to the gateway again:

  | Reset | Wi-Fi back after | Oops / BUG / WARN in `journalctl -k` |
  |---|---|---|
  | 1 | 8.4 s | 0 |
  | 2 | 9.4 s | 0 |
  | 3 | 5.1 s | 0 |

- The whole boot's kernel log had no Oops, BUG, Call trace, WARNING, hung task or soft
  lockup. The machine stayed up and responsive: SSH over Tailscale (over this Wi-Fi) worked
  right after the run, with no reboot since the one into n1x2.
- `check.sh` gave 20 OK, 1 WARN (no USB4 device attached), 0 FAIL.
- `install.sh --default` then made 7.3.0-n1x2 GRUB's default.

The forced reset was not run on an unpatched kernel: there it hangs the machine. The roaming
MCU timeout that set this off was not reproduced; the forced reset covers the same
`mt7925e_mac_reset` path.
