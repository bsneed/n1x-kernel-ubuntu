/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * n1x-kernel-ubuntu - the rest of i2c-hid-core.c that 0002's code calls, faked for harness.c.
 * Included after the extracted types and before the extracted functions. These are stock
 * functions that 0002 doesn't change (tests/t-patch.sh pins the ones it must not change); the
 * fake device behind them answers from the scripts in W.
 */

struct i2chid_ops {
	int (*power_up)(struct i2chid_ops *ops);
	void (*power_down)(struct i2chid_ops *ops);
	void (*restore_sequence)(struct i2chid_ops *ops);
	void (*shutdown_tail)(struct i2chid_ops *ops);
};

static int i2c_hid_parse(struct hid_device *hid);
static const struct hid_ll_driver i2c_hid_ll_driver = { .parse = i2c_hid_parse };
static struct i2c_hid_desc fake_desc; /* what the device answers to a descriptor read */

/*
 * The report descriptors the fake device can send (all RDESC_LEN bytes, the length its HID
 * descriptor gives), and whether 7.3's hid_open_report() rejects each one: hid_parse_collections()
 * fails on a long item, an item that doesn't fit, an end without a begin collection and a
 * collection left open; an unknown main item (0x00) only warns, and push/pop are global items.
 */
#define RDESC_LEN 33
enum { RD_VALID, RD_NESTED, RD_CUT, RD_ZEROS, RD_UNDERFLOW, RD_LONG, RD_PAST_END, RD_N };
static const struct fake_rdesc {
	const char *name;
	u8 b[RDESC_LEN];
	bool core_rejects;
	const char *why;	/* what 0002's check says */
} fake_rdescs[RD_N] = {
	/* a keyboard: a 4-byte Logical Maximum (1) and a 2-byte Report Count (1), exactly RDESC_LEN */
	{ "valid", { 0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0x05, 0x07, 0x19, 0xe0, 0x29, 0xe7, 0x15, 0x00,
		     0x27, 0x01, 0x00, 0x00, 0x00, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x96, 0x01, 0x00,
		     0x75, 0x08, 0x81, 0x01, 0xc0 }, false, NULL },
	/* a mouse: nested collections, a push and a pop (global tags 10 and 11), zero padding */
	{ "nested, padded", { 0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x09, 0x01, 0xa1, 0x00, 0x05, 0x09,
			      0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01, 0x95, 0x03, 0x75, 0x01,
			      0x81, 0x02, 0xc0, 0xc0, 0xa4, 0xb4 }, false, NULL },
	/* what ASTH0001 sent: the start of one, then zeros */
	{ "cut short", { 0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0x05, 0x07 }, true, "unbalanced collection" },
	{ "zeros", { 0 }, false, "no collection" },
	{ "end before begin", { 0x05, 0x01, 0x09, 0x06, 0xc0, 0xa1, 0x01 }, true,
	  "end of a collection never opened" },
	/* a long item (0xfe, 2 data bytes) after a whole collection */
	{ "long item", { 0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0xc0, 0xfe, 0x02, 0x00 }, true, "long item" },
	/* a whole collection, then a 4-byte Logical Maximum with 3 bytes left */
	{ "item past the end", { 0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0xc0, [29] = 0x27, 0x01, 0x00, 0x00 },
	  true, "item past the end" },
};
static bool fake_core_rejects(const u8 *rdesc, unsigned int rsize)
{
	for (int i = 0; i < RD_N; i++)
		if (rsize == RDESC_LEN && !memcmp(rdesc, fake_rdescs[i].b, RDESC_LEN))
			return fake_rdescs[i].core_rejects;
	bad("unknown-report-descriptor");
	return true;
}

static inline u32 i2c_hid_lookup_quirk(const u16 vendor, const u16 product)
{
	(void)vendor; (void)product;
	return W.quirks;
}
static inline u32 i2c_hid_get_dmi_quirks(const u16 vendor, const u16 product)
{
	(void)vendor; (void)product;
	return 0;
}
static inline struct i2c_hid_desc *i2c_hid_get_dmi_i2c_hid_desc_override(const char *name)
{
	(void)name;
	return NULL;
}
static inline char *i2c_hid_get_dmi_hid_report_desc_override(const char *name, unsigned int *size)
{
	(void)name; (void)size;
	return NULL;
}

/* The reset handshake of parse: power-up and reset failures there are W.add's */
static inline int i2c_hid_start_hwreset(struct i2c_hid *ihid) { (void)ihid; return 0; }
static inline int i2c_hid_finish_hwreset(struct i2c_hid *ihid) { (void)ihid; return 0; }

static inline int i2c_hid_read_register(struct i2c_hid *ihid, __le16 reg, void *buf, size_t len)
{
	int ret;

	if (reg == ihid->hdesc.wReportDescRegister && len == RDESC_LEN) {
		ret = script_next(&W.rdesc);
		W.rdesc_reads++;
		if (ret < 0 || ret >= RD_N) {
			bad("no-such-report-descriptor");
			return -EIO;
		}
		memcpy(buf, fake_rdescs[ret].b, len);
		return 0;
	}
	TRACE("desc ");
	if (reg != ihid->wHIDDescRegister || len != sizeof(struct i2c_hid_desc)) {
		bad("unexpected-read");
		return -EIO;
	}
	ret = script_next(&W.desc);
	if (ret) {
		memset(buf, 0xff, len); /* what a failed read leaves can be garbage */
		if (ret == -ETIMEDOUT)
			advance_ms(W.timeout_ms);
		return ret;
	}
	memcpy(buf, &fake_desc, len);
	return 0;
}

/* Only the retry's HID RESET comes through here (SET_POWER is i2c_hid_set_power, faked) */
static inline int i2c_hid_xfer(struct i2c_hid *ihid, u8 *send, int send_len, u8 *recv, int recv_len)
{
	int ret;

	(void)recv;
	if (!ihid->cmd_lock.held)
		bad("xfer-without-cmd-lock");
	if (send_len != 4 || recv_len || send[2] != 0x00 || send[3] != I2C_HID_OPCODE_RESET) {
		bad("unexpected-xfer");
		return -EIO;
	}
	TRACE("reset ");
	addf(W.resets, sizeof(W.resets), "%02x%02x ", send[1], send[0]);
	ret = script_next(&W.reset);
	if (ret == -ETIMEDOUT)
		advance_ms(W.timeout_ms);
	return ret;
}

static inline int i2c_hid_set_power(struct i2c_hid *ihid, int power_state)
{
	TRACE("set_power(%d) ", power_state);
	W.set_powers++;
	if (!(ihid->hid->status & HID_STAT_ADDED))
		bad("set-power-of-down-device");
	return power_state == I2C_HID_PWR_ON ? script_next(&W.set_power) : 0;
}

static inline irqreturn_t i2c_hid_irq(int irq, void *dev_id)
{
	(void)irq; (void)dev_id;
	return 0;
}

static inline void ihid_core_panel_follower_work(struct work_struct *work) { (void)work; }

static inline int i2c_hid_core_register_panel_follower(struct i2c_hid *ihid)
{
	(void)ihid;
	TRACE("follow ");
	return script_next(&W.follower_reg);
}

static inline int i2c_hid_alloc_buffers(struct i2c_hid *ihid, size_t report_size)
{
	ihid->cmdbuf = calloc(1, report_size + 16);
	ihid->bufsize = report_size;
	W.allocs++;
	return 0;
}

static inline void i2c_hid_free_buffers(struct i2c_hid *ihid)
{
	free(ihid->cmdbuf);
	ihid->cmdbuf = NULL;
	ihid->bufsize = 0;
	W.frees++;
}

/* Stock's suspend and resume of a device that is up, as far as the IRQ and power go */
static inline int i2c_hid_core_suspend(struct i2c_hid *ihid, bool force_poweroff)
{
	TRACE("suspend ");
	W.suspends++;
	W.forced_suspends += force_poweroff;
	if (!(ihid->hid->status & HID_STAT_ADDED) || !W.irq_requested)
		bad("suspend-of-down-device");
	disable_irq(ihid->client->irq);
	if ((force_poweroff || !device_may_wakeup(&ihid->client->dev)) && ihid->ops->power_down)
		ihid->ops->power_down(ihid->ops);
	return 0;
}

static inline int i2c_hid_core_resume(struct i2c_hid *ihid)
{
	TRACE("resume ");
	W.resumes++;
	if (!(ihid->hid->status & HID_STAT_ADDED) || !W.irq_requested)
		bad("resume-of-down-device");
	if (!device_may_wakeup(&ihid->client->dev) && ihid->ops->power_up)
		ihid->ops->power_up(ihid->ops);
	enable_irq(ihid->client->irq);
	return 0;
}
