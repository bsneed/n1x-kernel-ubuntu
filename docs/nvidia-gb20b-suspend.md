# NVIDIA 620: system suspend refused on the N1x GPU (GB20B)

This file explains `patches/nvidia/0010-let-the-n1x-gpu-go-through-system-suspend-again.patch`
and holds a draft bug report for
[NVIDIA/open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules/issues).
The report has not been filed.

## What 620 changed

In 615.78.08, RM marks a GPU as not supporting power management through the
`PDB_PROP_GPU_POWER_MANAGEMENT_UNSUPPORTED` property. That property is set only for GH100, GB100,
GB102, GB110, GB112 and GR100 (`src/nvidia/generated/g_gpu_nvoc.c`).

620.73.04 replaces the property with the HAL function `gpuIsPowerManagementUnsupported()`. That
function returns `NV_TRUE` for the same chips **plus GB20B and GB20C**. Its result becomes
`nv->is_pm_unsupported` in `RmInitPowerManagement()`
(`src/nvidia/arch/nvalloc/unix/src/dynamic-power.c`), and the kernel interface checks it in two
places:

- `nv_suspend_devices()`, which the PM notifier calls on `PM_SUSPEND_PREPARE`, returns
  `NV_ERR_NOT_SUPPORTED`.
- `nvidia_suspend()` returns `NV_ERR_NOT_SUPPORTED`.

GB20B is the integrated GPU of the N1x laptops: RTX Spark N1X, PCI IDs 2E03, 2E06 and 2E13.
It appears to be DGX Spark's GB10 (2E12) too: 620's README lists 2E12 "NVIDIA GB10" among the
N1x IDs, and NVIDIA added GB20B and GB20C to the list together, which suggests GB10 was the
target. That is not confirmed (it needs `PMC_BOOT_42` read on a DGX Spark).
On the ProArt P16, `PMC_BOOT_42` reads 0x1bba1000, which is architecture 0x1B (GB200) and
implementation 0xB (GB20B). With 620, every s2idle attempt on the laptop is refused before any
device suspends:

```
PM: suspend entry (s2idle)
NVRM: PM suspend notifier failed: 0x56
PM: suspend exit
systemd-sleep: Failed to put system to sleep. System resumed again: Operation not permitted
```

`/sys/power/suspend_stats` then counts failures and no successes. The result is the same from
logind (`systemctl suspend`, so with `nvidia-suspend.service`) and from `/sys/power/state`.

## The patch

0010 leaves the three N1x laptop devices out of the check, by PCI vendor and device ID:

```c
nv->is_pm_unsupported = gpuIsPowerManagementUnsupported(pGpu) &&
                        !RmIsN1xLaptopGpu(nv);   /* 10de:2e03, 2e06, 2e13 */
```

Every other chip on 620's list keeps 620's behaviour: GB20C, and every other GB20B part, GB10
(DGX Spark) included, whatever NVIDIA's reason for listing it. This is the only place the flag
is set (`dynamic-power.c`); it is read only by `nv_suspend_devices()` and `nvidia_suspend()`.
The rest of the suspend path is unchanged from 615. That 615 suspends and resumes on these
laptops rests on Omarchy, which ships 615.78.08 with this 7.3 recipe and its N1x s2idle work; it
was not tested here (Ubuntu's 615.71.09 modules don't build on 7.3; see the README).

## Evidence

ASUS ProArt P16 H7607BA, BIOS H7607BA.300, kernel 7.3.0-n1x1, NVIDIA 620.73.04 with
`patches/nvidia` 0003–0010, `NVreg_PreserveVideoMemoryAllocations=1`, and
`UseKernelSuspendNotifiers=1` (the default). Sleep mode is s2idle. A CalDigit TS5 Plus and a Dell
U4025QW were connected over USB4.

- Without 0010: 5 of 5 attempts were refused with `0x56`, all in the PM notifier.
- With 0010: 4 of 4 suspend/resume cycles succeeded (one machine, one evening: a small sample) (`suspend_stats` success=4, fail=0). One run
  traced the path: `nv_uvm_suspend`, `RmUpdateFixedFbsrModes`, `gpuEnterStandby` and both
  `rm_power_management` calls (suspend and resume) returned `NV_OK`. After every resume:
  - there was no Xid or GSP error;
  - eDP-1 and the USB4 monitor (DP-8) were connected, and the USB4 domains and dock re-enumerated;
  - the dock's 10GbE relinked at 10000 Mb/s;
  - `nvidia-smi` was healthy.

## Dropping the patch

Once NVIDIA's release no longer lists GB20B as unsupported, the check in
`RmInitPowerManagement()` changes or goes, and 0010 no longer applies: the build fails there
(patches are applied with `--forward --fuzz=0`, so one that no longer fits, or is already in,
is an error). When that happens:

1. Delete 0010.
2. Raise `NVIDIA_N1X_REVISION` in `sources`.
3. Rebuild, then test s2idle once (`journalctl -k | grep "PM suspend notifier"` must stay empty).

## Draft report

**Title:** 620.73.04: system suspend refused on RTX Spark N1X laptops (GB20B listed as PM-unsupported)

**Body:**

> On 620.73.04, every system suspend on an RTX Spark N1X laptop (ASUS ProArt P16 H7607BA,
> device 10de:2e06) fails in the PM notifier:
>
>     NVRM: PM suspend notifier failed: 0x56
>
> `gpuIsPowerManagementUnsupported()` returns true for GB20B and GB20C in 620.73.04
> (`g_gpu_nvoc.c`), so `nv->is_pm_unsupported` is set and `nv_suspend_devices()` returns
> `NV_ERR_NOT_SUPPORTED`. In 615.78.08 the corresponding property
> (`PDB_PROP_GPU_POWER_MANAGEMENT_UNSUPPORTED`) did not include GB20B, and s2idle works on these
> laptops (as shipped by Omarchy, 615.78.08 on 7.3).
>
> With `is_pm_unsupported` cleared for these three device IDs, s2idle suspend and resume work
> on 620.73.04 too: 4/4 cycles on one ProArt P16, no Xid or GSP errors, and displays and USB4
> come back.
>
> GB20B is the integrated GPU of a laptop, where s2idle is required. Could GB20B be dropped from
> that list, or N1x (2E03/2E06/2E13) be told apart from the parts the list is meant for?
>
> Environment: Ubuntu 26.04 arm64, kernel 7.3, BIOS H7607BA.300,
> `NVreg_PreserveVideoMemoryAllocations=1`, mem_sleep `[s2idle]`.
