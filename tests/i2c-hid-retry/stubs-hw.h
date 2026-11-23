/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * n1x-kernel-ubuntu - the rest of stubs.h: the IRQ, the delayed work, the hid device, DMI and panel
 * followers, faked. Included by stubs.h.
 */

/* --- IRQ ---------------------------------------------------------------------------------------- */
#define IRQF_TRIGGER_LOW	0x00000008
#define IRQF_ONESHOT		0x00002000
#define IRQF_NO_AUTOEN		0x00080000
static inline unsigned int irq_get_trigger_type(unsigned int irq) { (void)irq; return 0; }
static inline int request_threaded_irq(unsigned int irq, void *handler, irqreturn_t (*fn)(int, void *),
				       unsigned long flags, const char *name, void *dev)
{
	int ret;

	(void)irq; (void)handler; (void)fn; (void)name; (void)dev;
	TRACE("irq ");
	if (W.irq_requested) {
		bad("irq-requested-twice");
		return -EBUSY;
	}
	ret = script_next(&W.irq);
	if (ret)
		return ret;
	W.irq_requested = true;
	W.irq_requests++;
	W.irq_depth = flags & IRQF_NO_AUTOEN ? 1 : 0;
	return 0;
}
static inline void free_irq(unsigned int irq, void *dev)
{
	(void)irq; (void)dev;
	TRACE("free_irq ");
	if (!W.irq_requested) {
		bad("free-of-free-irq");
		return;
	}
	W.irq_requested = false;
	W.irq_frees++;
}
static inline void enable_irq(unsigned int irq)
{
	(void)irq;
	if (!W.irq_requested)
		bad("enable-of-free-irq");
	else if (W.irq_depth == 0)
		bad("unbalanced-enable-irq");
	else
		W.irq_depth--;
}
static inline void disable_irq(unsigned int irq)
{
	(void)irq;
	if (!W.irq_requested)
		bad("disable-of-free-irq");
	else
		W.irq_depth++;
}

/* --- the delayed work ----------------------------------------------------------------------------- */
struct workqueue_struct { const char *name; };
static struct workqueue_struct wq_freezable = { "system_freezable_wq" }, wq_plain = { "system_wq" };
static struct workqueue_struct *system_freezable_wq = &wq_freezable;
static struct workqueue_struct *system_wq __attribute__((unused)) = &wq_plain; /* a mutant's */
struct work_struct { void (*func)(struct work_struct *); };
struct delayed_work {
	struct work_struct work;
	bool pending;
	unsigned long due;
	struct workqueue_struct *wq;
};
#define INIT_WORK(w, f) ((w)->func = (f))
#define INIT_DELAYED_WORK(d, f) ((d)->work.func = (f), (d)->pending = false)
#define to_delayed_work(w) container_of(w, struct delayed_work, work)
static inline bool queue_delayed_work(struct workqueue_struct *wq, struct delayed_work *dw, unsigned long delay)
{
	addf(W.delays, sizeof(W.delays), "%u ", jiffies_to_msecs(delay));
	if (wq != system_freezable_wq)
		bad("not-the-freezable-workqueue");
	if (dw->pending)
		return false;
	dw->pending = true;
	dw->due = jiffies + delay;
	dw->wq = wq;
	return true;
}
static inline bool cancel_delayed_work_sync(struct delayed_work *dw)
{
	bool was = dw->pending;

	W.cancels++;
	dw->pending = false;
	return was;
}

/* --- hid ------------------------------------------------------------------------------------------- */
#define HID_MIN_BUFFER_SIZE	64
#define HID_STAT_ADDED		BIT(0)
#define BUS_I2C			0x18
struct hid_ll_driver { int dummy; };
struct hid_device {
	struct device dev;
	unsigned int status;
	__u16 bus;
	u32 vendor, product, version;
	unsigned long initial_quirks;
	char name[128], phys[64];
	void *driver_data;
	const struct hid_ll_driver *ll_driver;
};
static inline struct hid_device *hid_allocate_device(void) { return calloc(1, sizeof(struct hid_device)); }
static inline int hid_add_device(struct hid_device *hid)
{
	int ret;

	TRACE("add ");
	if (hid->status & HID_STAT_ADDED) {
		bad("hid-added-twice");
		return -EBUSY;
	}
	ret = script_next(&W.add);
	if (!ret) {
		hid->status |= HID_STAT_ADDED;
		W.adds++;
	}
	return ret;
}
static inline void hid_destroy_device(struct hid_device *hid)
{
	(void)hid;
	if (W.destroys++)
		bad("hid-destroyed-twice");
}
#define strscpy(d, s, n) snprintf(d, n, "%s", s)

/* --- DMI (DMI_MATCH is a substring match, as dmi_matches() does it) -------------------------------- */
enum dmi_field { DMI_NONE, DMI_SYS_VENDOR, DMI_PRODUCT_NAME };
struct dmi_strmatch { unsigned char slot; char substr[79]; };
struct dmi_system_id {
	const char *ident;
	struct dmi_strmatch matches[4];
};
#define DMI_MATCH(a, b) { .slot = a, .substr = b }
static inline int dmi_check_system(const struct dmi_system_id *list)
{
	int count = 0;

	for (const struct dmi_system_id *d = list; d->matches[0].slot != DMI_NONE; d++) {
		bool all = true;

		for (int i = 0; i < 4 && d->matches[i].slot != DMI_NONE; i++) {
			const char *s = d->matches[i].slot == DMI_SYS_VENDOR ? W.vendor : W.product;

			all = all && s && strstr(s, d->matches[i].substr);
		}
		count += all;
	}
	return count;
}

/* --- panel followers -------------------------------------------------------------------------------- */
struct drm_panel_follower { int dummy; };
static inline bool drm_is_panel_follower(struct device *dev) { (void)dev; return W.follower; }
static inline void drm_panel_remove_follower(struct drm_panel_follower *f) { (void)f; W.follower_removes++; }
