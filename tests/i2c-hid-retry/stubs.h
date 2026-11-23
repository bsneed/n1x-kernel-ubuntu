/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * n1x-kernel-ubuntu - the kernel API that patches/ubuntu/0002's code in i2c-hid-core.c uses,
 * faked for tests/i2c-hid-retry/harness.c: time (jiffies, msleep), the delayed work, the IRQ,
 * the hid device, wakeup, DMI and the log (the IRQ, work, hid, DMI and panel parts in
 * stubs-hw.h). Every fake records what it was asked to do in W, and a misuse that would WARN or
 * corrupt state in a real kernel (freeing an IRQ that isn't requested, adding a hid twice, ...)
 * is recorded in W.bad.
 */
#define _GNU_SOURCE /* memmem */
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Linux's errno values (the host's can differ: macOS has ETIMEDOUT 60) */
#define EIO		5
#define ENXIO		6
#define ENOMEM		12
#define EBUSY		16
#define EEXIST		17
#define ENODEV		19
#define EINVAL		22
#define ETIMEDOUT	110
#define EPROBE_DEFER	517

typedef uint8_t u8;
typedef uint16_t u16, __u16;
typedef uint32_t u32;
typedef uint16_t __le16;
typedef uint32_t __le32;
typedef int irqreturn_t;
typedef int wait_queue_head_t;

#define __packed __attribute__((packed))
#define BIT(n) (1UL << (n))
#define container_of(p, type, member) ((type *)((char *)(p) - offsetof(type, member)))
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x, v) ((x) = (v))
#define smp_wmb() __sync_synchronize()
#define smp_rmb() __sync_synchronize()
#define IS_ERR(p) ((uintptr_t)(p) >= (uintptr_t)-4095)
#define PTR_ERR(p) ((long)(intptr_t)(p))
#define GFP_KERNEL 0
#define EXPORT_SYMBOL_GPL(s)

static inline u16 le16_to_cpu(__le16 v)
{
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
	return __builtin_bswap16(v);
#else
	return v;
#endif
}
#define cpu_to_le16(v) le16_to_cpu(v)

/* --- the world the fakes record into ------------------------------------------------------ */
struct script { int v[32]; int n, i, dflt; }; /* results, one per call; then dflt */
static int script_next(struct script *s) { return s->i < s->n ? s->v[s->i++] : s->dflt; }

static struct world {
	const char *vendor, *product;	/* DMI sys_vendor, product_name */
	bool follower;			/* drm_is_panel_follower() */
	unsigned int timeout_ms;	/* what a transfer that times out takes */
	unsigned long quirks;		/* i2c_hid_lookup_quirk() */
	struct script power_up, addr, desc, reset, irq, add, set_power, follower_reg;
	char bad[512];			/* misuses, comma-separated */
	char log[8192];			/* "level: message|" for dev_info/warn/err, hid_err */
	char trace[8192];		/* the calls of each attempt, space-separated */
	char delays[2048];		/* each queue_delayed_work delay, in ms */
	char starts[2048];		/* each power-up, in ms after the failure (retries only) */
	char resets[512];		/* the command register of each RESET */
	bool irq_requested;
	int irq_depth, irq_requests, irq_frees;
	int adds, destroys, ups, downs, allocs, frees, cancels;
	int suspends, forced_suspends, resumes, set_powers, tails, restores, follower_removes;
	unsigned int sleeps_ms;
} W;

static void bad(const char *what)
{
	strncat(W.bad, what, sizeof(W.bad) - strlen(W.bad) - 2);
	strcat(W.bad, ",");
}

static void addf(char *buf, size_t size, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
static void addf(char *buf, size_t size, const char *fmt, ...)
{
	size_t len = strlen(buf);
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf + len, size - len, fmt, ap);
	va_end(ap);
}
#define TRACE(...) addf(W.trace, sizeof(W.trace), __VA_ARGS__)

/* --- log ---------------------------------------------------------------------------------- */
static void log_add(const char *level, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void log_add(const char *level, const char *fmt, ...)
{
	char line[512];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(line, sizeof(line), fmt, ap);
	va_end(ap);
	line[strcspn(line, "\n")] = 0;
	addf(W.log, sizeof(W.log), "%s: %s|", level, line);
}
#define dev_info(d, ...) ((void)(d), log_add("info", __VA_ARGS__))
#define dev_warn(d, ...) ((void)(d), log_add("warn", __VA_ARGS__))
#define dev_err(d, ...) ((void)(d), log_add("err", __VA_ARGS__))
#define hid_err(h, ...) ((void)(h), log_add("err", __VA_ARGS__))
#define dev_dbg(d, ...) ((void)(d))
#define dbg_hid(...) ((void)0)

/* --- time ----------------------------------------------------------------------------------- */
#define HZ 250
static unsigned long jiffies;
static inline unsigned long msecs_to_jiffies(unsigned int ms) { return (ms * (unsigned long)HZ + 999) / 1000; }
static inline unsigned int jiffies_to_msecs(unsigned long j) { return j * (1000 / HZ); }
#define time_after(a, b) ((long)((b) - (a)) < 0)
#define time_before(a, b) time_after(b, a)
#define time_before_eq(a, b) ((long)((b) - (a)) >= 0)
static void advance_ms(unsigned int ms) { jiffies += msecs_to_jiffies(ms); }
static inline void msleep(unsigned int ms) { TRACE("msleep(%u) ", ms); W.sleeps_ms += ms; advance_ms(ms); }
static inline void usleep_range(unsigned long a, unsigned long b) { (void)a; (void)b; }

/* --- locks ------------------------------------------------------------------------------------ */
struct mutex { int held; };
static inline void mutex_init(struct mutex *m) { m->held = 0; }
static inline void mutex_lock(struct mutex *m) { if (m->held++) bad("mutex-deadlock"); }
static inline void mutex_unlock(struct mutex *m) { if (m->held-- != 1) bad("mutex-unbalanced"); }
#define scoped_guard(type, lock) \
	for (int _sg = (type##_lock(lock), 1); _sg; _sg = (type##_unlock(lock), 0))
#define init_waitqueue_head(w) ((void)(w))

/* --- devices, I2C ------------------------------------------------------------------------------ */
struct device {
	void *driver_data;
	struct device *parent;
	const char *name;
	bool can_wakeup, wakeup;
	int wakeup_enables, wakeup_disables;
};
static inline const char *dev_name(const struct device *dev) { return dev->name; }
static inline void device_enable_async_suspend(struct device *dev) { (void)dev; }
static inline bool device_may_wakeup(struct device *dev) { return dev->can_wakeup && dev->wakeup; }
static inline void device_wakeup_disable(struct device *dev)
{
	if (dev->can_wakeup) {
		dev->wakeup = false;
		dev->wakeup_disables++;
	}
}
static inline int device_wakeup_enable(struct device *dev)
{
	if (!dev->can_wakeup)
		return -EINVAL;
	if (dev->wakeup)
		return -EEXIST;
	dev->wakeup = true;
	dev->wakeup_enables++;
	return 0;
}
static inline void *devm_kzalloc(struct device *dev, size_t size, int gfp)
{
	(void)dev; (void)gfp;
	return calloc(1, size);
}

#define I2C_M_RD	0x0001
#define I2C_M_TEN	0x0010
#define I2C_M_DMA_SAFE	0x0200
struct i2c_adapter { int nr; };
struct i2c_client {
	unsigned short flags, addr;
	char name[20];
	struct i2c_adapter *adapter;
	struct device dev;
	int irq;
};
#define to_i2c_client(d) container_of(d, struct i2c_client, dev)
static inline void *i2c_get_clientdata(const struct i2c_client *c) { return c->dev.driver_data; }
static inline void i2c_set_clientdata(struct i2c_client *c, void *data) { c->dev.driver_data = data; }
static inline int i2c_smbus_read_byte(const struct i2c_client *c)
{
	int ret = script_next(&W.addr);

	(void)c;
	TRACE("addr ");
	if (ret == -ETIMEDOUT)
		advance_ms(W.timeout_ms);
	return ret;
}

#include "stubs-hw.h"
