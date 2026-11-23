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

static const struct hid_ll_driver i2c_hid_ll_driver;
static struct i2c_hid_desc fake_desc; /* what the device answers to a descriptor read */

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

static inline int i2c_hid_read_register(struct i2c_hid *ihid, __le16 reg, void *buf, size_t len)
{
	int ret;

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
