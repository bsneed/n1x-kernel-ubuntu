// SPDX-License-Identifier: GPL-2.0-only
/*
 * n1x-kernel-ubuntu - runs patches/ubuntu/0002's probe retry, as patched into 7.3's
 * i2c-hid-core.c, against a fake I2C HID device, with the host's C compiler.
 *
 * Why: the retry's state machine (defer, retry, give up, and remove, shutdown and system sleep
 * in every state) decides whether a ProArt P16's keyboard comes back, and whether a kernel
 * WARNs, leaks an IRQ or skips a resume; none of that is visible to a grep of the source.
 *
 * tests/t-i2c-hid-retry.sh applies 0002 to the fixture, extracts the patched types (core-types.h)
 * and functions (core-funcs.h) from it, and builds this file:
 *   stubs.h       the kernel API, faked (time, IRQ, delayed work, hid, wakeup, DMI, log), with
 *                 stubs-hw.h
 *   core-types.h  extracted: the defines, enum and structs, the DMI table
 *   driver.h      the stock i2c-hid functions 0002 calls, faked, and the fake device
 *   core-funcs.h  extracted: 0002's functions, and the stock ones it changes or calls
 *   cases-*.c     the scenarios
 * Each check prints "CHECK<TAB>name<TAB>expected<TAB>actual"; the script compares them.
 */
#include "stubs.h"
#include "core-types.h"
#include "driver.h"
#include "core-funcs.h"

static struct i2c_adapter adapter;
static struct i2c_client client;
static struct i2chid_ops ops;
static char scenario[160];
static int checks;

static struct i2c_hid *ih(void) { return i2c_get_clientdata(&client); }

static int fake_power_up(struct i2chid_ops *o)
{
	struct i2c_hid *ihid = ih();
	int ret = script_next(&W.power_up);

	(void)o;
	TRACE("power_up ");
	if (ihid && ihid->probe_retry_state == I2C_HID_PROBE_RETRY_PENDING)
		addf(W.starts, sizeof(W.starts), "%u ", jiffies_to_msecs(jiffies - ihid->probe_retry_start));
	if (ret == -ETIMEDOUT)
		advance_ms(W.timeout_ms);
	else if (!ret)
		W.ups++;
	return ret;
}
static void fake_power_down(struct i2chid_ops *o) { (void)o; TRACE("power_down "); W.downs++; }
static void fake_restore(struct i2chid_ops *o) { (void)o; W.restores++; }
static void fake_tail(struct i2chid_ops *o) { (void)o; W.tails++; }

/* A new world: a ProArt P16 whose touchpad answers everything, wakeup enabled */
static void begin(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void begin(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(scenario, sizeof(scenario), fmt, ap);
	va_end(ap);
	memset(&W, 0, sizeof(W));
	W.vendor = "ASUS";
	W.product = "ProArt P16 H7607BA";
	W.timeout_ms = 2000;
	memset(&client, 0, sizeof(client));
	client.addr = 0x15;
	client.irq = 72;
	client.adapter = &adapter;
	snprintf(client.name, sizeof(client.name), "3030443150435341:00");
	client.dev.name = "i2c-3030443150435341:00";
	client.dev.can_wakeup = client.dev.wakeup = true;
	ops = (struct i2chid_ops){ fake_power_up, fake_power_down, fake_restore, fake_tail };
	memset(&fake_desc, 0, sizeof(fake_desc));
	fake_desc.wHIDDescLength = cpu_to_le16(sizeof(fake_desc));
	fake_desc.bcdVersion = cpu_to_le16(0x0100);
	fake_desc.wCommandRegister = cpu_to_le16(0x0022);
	fake_desc.wReportDescLength = cpu_to_le16(RDESC_LEN);
	fake_desc.wReportDescRegister = cpu_to_le16(0x0020);
	fake_desc.wVendorID = cpu_to_le16(0x093a);
	fake_desc.wProductID = cpu_to_le16(0x4f01);
	jiffies = 100000; /* not 0: an elapsed time measured from boot shows */
}

#define SCRIPT(s, ...) script_set(&(s), (int[]){ __VA_ARGS__ }, sizeof((int[]){ __VA_ARGS__ }) / sizeof(int))
static void script_set(struct script *s, const int *v, size_t n)
{
	memcpy(s->v, v, n * sizeof(*v));
	s->n = n;
	s->i = 0;
}

static int probe(void) { return i2c_hid_core_probe(&client, &ops, 0x0001, 0); }
static void do_remove(void) { i2c_hid_core_remove(&client); }
static void do_shutdown(void) { i2c_hid_core_shutdown(&client); }
static int pm_suspend(void) { return i2c_hid_core_pm_suspend(&client.dev); }
static int pm_resume(void) { return i2c_hid_core_pm_resume(&client.dev); }
static int pm_restore(void) { return i2c_hid_core_pm_restore(&client.dev); }

/* Run the queued retry, when it is due (time jumps there); false if none is queued */
static bool run_work(void)
{
	struct delayed_work *dw = &ih()->probe_retry_work;

	if (!dw->pending)
		return false;
	if (time_before(jiffies, dw->due))
		jiffies = dw->due;
	dw->pending = false;
	TRACE("| ");
	dw->work.func(&dw->work);
	return true;
}
static int run_all(void)
{
	int n = 0;

	while (n < 200 && run_work())
		n++;
	return n;
}

static const char *state_name(void)
{
	static const char *const names[] = { "NONE", "PENDING", "UP", "GAVE_UP" };
	unsigned int s = ih()->probe_retry_state;

	return s < 4 ? names[s] : "?";
}

/* What the device holds: state, IRQ (requests/frees), hid, power, wakeup, the work, buffers */
static const char *snap(void)
{
	static char s[640];

	snprintf(s, sizeof(s),
		 "state=%s irq=%s req=%d free=%d add=%d destroy=%d up=%d down=%d wake=%s work=%s bufs=%d/%d bad=%s",
		 state_name(), !W.irq_requested ? "free" : W.irq_depth ? "disabled" : "enabled",
		 W.irq_requests, W.irq_frees, W.adds, W.destroys, W.ups, W.downs,
		 device_may_wakeup(&client.dev) ? "on" : "off",
		 ih()->probe_retry_work.pending ? "queued" : "idle", W.allocs, W.frees, W.bad);
	return s;
}

/* What was done to it: stock suspend (forced), resume, SET_POWER, shutdown_tail, restore */
static const char *calls(void)
{
	static char s[160];

	snprintf(s, sizeof(s), "suspend=%d/%d resume=%d set_power=%d tail=%d restore=%d",
		 W.suspends, W.forced_suspends, W.resumes, W.set_powers, W.tails, W.restores);
	return s;
}

/* The log lines containing NEEDLE, "|"-separated */
static const char *log_find(const char *needle)
{
	static char out[32768];
	const char *p = W.log, *e;

	out[0] = 0;
	for (; (e = strchr(p, '|')); p = e + 1) {
		if (memmem(p, e - p, needle, strlen(needle)))
			addf(out, sizeof(out), "%s%.*s", out[0] ? "|" : "", (int)(e - p), p);
	}
	return out;
}

/* The calls of retry N (1-based), from the trace */
static const char *attempt(int n)
{
	static char out[1024];
	const char *p = W.trace, *e;

	for (int i = 0; i < n && p; i++)
		p = strstr(p, "| ") ? strstr(p, "| ") + 2 : NULL;
	if (!p)
		return "(none)";
	e = strstr(p, "| ");
	snprintf(out, sizeof(out), "%.*s", (int)(e ? e - p : (long)strlen(p)), p);
	if (out[0] && out[strlen(out) - 1] == ' ')
		out[strlen(out) - 1] = 0;
	return out;
}

/* How many log lines contain NEEDLE */
static int count_lines(const char *needle)
{
	const char *p = W.log, *e;
	int n = 0;

	for (; (e = strchr(p, '|')); p = e + 1)
		n += memmem(p, e - p, needle, strlen(needle)) != NULL;
	return n;
}

static void check(const char *name, const char *expected, const char *actual)
{
	checks++;
	printf("CHECK\t%s: %s\t%s\t%s\n", scenario, name, expected, actual);
}
static void checki(const char *name, long expected, long actual)
{
	char e[32], a[32];

	snprintf(e, sizeof(e), "%ld", expected);
	snprintf(a, sizeof(a), "%ld", actual);
	check(name, e, a);
}

#include "cases-probe.c"
#include "cases-teardown.c"
#include "cases-rdesc.c"

int main(void)
{
	cases_probe();
	cases_teardown();
	cases_rdesc();
	printf("DONE\t%d\n", checks);
	return 0;
}
