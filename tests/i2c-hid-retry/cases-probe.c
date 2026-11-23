// SPDX-License-Identifier: GPL-2.0-only
/*
 * n1x-kernel-ubuntu - harness.c's scenarios of probe and the retries: which machines and errors
 * defer, what a deferred device holds, retries that fail, succeed or give up, and their timing.
 * Included by harness.c.
 */

#define DEFERRED "state=PENDING irq=free req=0 free=0 add=0 destroy=0 up=1 down=1 wake=on work=queued bufs=1/0 bad="
#define FAILED "state=NONE irq=free req=0 free=0 add=0 destroy=1 up=1 down=1 wake=on work=idle bufs=1/1 bad="
#define FAILED_LOG "info: probe failed (-110), retrying every 5 s for up to 120 s"

static void stock_probe_failures(void)
{
	static const char *const dmi[][2] = {
		{ "Dell Inc.", "XPS 13 9345" }, { "LENOVO", "H7607BA" },
		{ "ASUS", "Zenbook A14 UX3407QA" }, { NULL, NULL },
	};

	for (unsigned int i = 0; i < 4; i++) {
		begin("not a P16 (%s, %s)", dmi[i][0] ? dmi[i][0] : "no DMI", dmi[i][1] ? dmi[i][1] : "-");
		W.vendor = dmi[i][0];
		W.product = dmi[i][1];
		SCRIPT(W.desc, -ETIMEDOUT);
		checki("a descriptor timeout fails the probe with -ENODEV", -ENODEV, probe());
		check("torn down as stock", FAILED, snap());
		check("no retry", "", log_find("probe failed ("));
		check("nothing queued", "", W.delays);
	}
	begin("not a P16, nothing at the address");
	W.product = "XPS 13 9345";
	SCRIPT(W.addr, -ETIMEDOUT, -ETIMEDOUT);
	checki("probe fails with -ENXIO", -ENXIO, probe());
	check("torn down as stock", FAILED, snap());
	begin("not a P16, descriptor -ENXIO");
	W.vendor = "Dell Inc.";
	SCRIPT(W.desc, -ENXIO);
	checki("probe fails with -ENODEV", -ENODEV, probe());

	begin("P16, panel follower");
	W.follower = true;
	SCRIPT(W.follower_reg, -ETIMEDOUT);
	checki("probe fails as stock", -ETIMEDOUT, probe());
	check("torn down as stock",
	      "state=NONE irq=free req=1 free=1 add=0 destroy=1 up=0 down=0 wake=on work=idle bufs=1/1 bad=", snap());
	check("no retry", "", W.delays);

	begin("P16, descriptor -EIO");
	SCRIPT(W.desc, -EIO);
	checki("probe fails with -ENODEV", -ENODEV, probe());
	check("torn down as stock", FAILED, snap());
	begin("P16, descriptor of HID 2.0");
	fake_desc.bcdVersion = cpu_to_le16(0x0200);
	checki("probe fails with -ENODEV", -ENODEV, probe());
	check("torn down as stock", FAILED, snap());
	begin("P16, power-up -EIO");
	SCRIPT(W.power_up, -EIO);
	checki("probe fails with -EIO", -EIO, probe());
	check("torn down as stock",
	      "state=NONE irq=free req=0 free=0 add=0 destroy=1 up=0 down=0 wake=on work=idle bufs=1/1 bad=", snap());
	begin("P16, IRQ busy");
	SCRIPT(W.irq, -EBUSY);
	checki("probe fails with -EBUSY", -EBUSY, probe());
	check("torn down as stock", FAILED, snap());
	begin("P16, hid add -ENODEV");
	SCRIPT(W.add, -ENODEV);
	checki("probe fails with -ENODEV", -ENODEV, probe());
	check("torn down as stock",
	      "state=NONE irq=free req=1 free=1 add=0 destroy=1 up=1 down=1 wake=on work=idle bufs=1/1 bad=", snap());
	begin("P16, QTEC re-power-on times out after the hid was added");
	W.quirks = I2C_HID_QUIRK_RE_POWER_ON;
	SCRIPT(W.set_power, -ETIMEDOUT);
	checki("probe fails as stock (the hid was added)", -ETIMEDOUT, probe());
	check("torn down as stock",
	      "state=NONE irq=free req=1 free=1 add=1 destroy=1 up=1 down=1 wake=on work=idle bufs=1/1 bad=", snap());
	check("no retry", "", W.delays);
}

static void deferred_probes(void)
{
	static const char *const vendors[] = { "ASUS", "ASUSTeK COMPUTER INC." }; /* DMI_MATCH: substring */

	for (unsigned int i = 0; i < 2; i++) {
		begin("P16 (%s), descriptor times out", vendors[i]);
		W.vendor = vendors[i];
		SCRIPT(W.desc, -ETIMEDOUT);
		checki("probe returns 0", 0, probe());
		check("deferred: nothing held, first retry queued", DEFERRED, snap());
		check("logged once, as info", FAILED_LOG, log_find("probe failed ("));
		check("the first retry 5 s after the failure", "5000 ", W.delays);
	}
	begin("P16, descriptor -ENXIO");
	SCRIPT(W.desc, -ENXIO);
	checki("probe returns 0", 0, probe());
	check("deferred", DEFERRED, snap());
	check("logged", "info: probe failed (-6), retrying every 5 s for up to 120 s", log_find("probe failed ("));
	begin("P16, nothing at the address");
	SCRIPT(W.addr, -ETIMEDOUT, -ETIMEDOUT);
	checki("probe returns 0", 0, probe());
	check("deferred", DEFERRED, snap());
	check("logged", "info: probe failed (-6), retrying every 5 s for up to 120 s", log_find("probe failed ("));
	begin("P16, power-up times out");
	SCRIPT(W.power_up, -ETIMEDOUT);
	checki("probe returns 0", 0, probe());
	check("deferred",
	      "state=PENDING irq=free req=0 free=0 add=0 destroy=0 up=0 down=0 wake=on work=queued bufs=1/0 bad=", snap());
	begin("P16, IRQ request -ENXIO");
	SCRIPT(W.irq, -ENXIO);
	checki("probe returns 0", 0, probe());
	check("deferred", DEFERRED, snap());
	begin("P16, hid add (parse) times out");
	SCRIPT(W.add, -ETIMEDOUT);
	checki("probe returns 0", 0, probe());
	check("deferred, its IRQ freed",
	      "state=PENDING irq=free req=1 free=1 add=0 destroy=0 up=1 down=1 wake=on work=queued bufs=1/0 bad=", snap());
}

static void retries(void)
{
	begin("retry 1 brings it up");
	SCRIPT(W.desc, -ETIMEDOUT);
	probe();
	checki("one retry ran", 1, run_all());
	check("up",
	      "state=UP irq=enabled req=1 free=0 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=", snap());
	check("logged as info", "info: probe retry 1 succeeded, 5000 ms after the probe failed", log_find("probe retry"));
	check("no give-up", "", log_find("giving up"));
	check("no RESET before a descriptor was read", "", W.resets);
	check("what it did", "power_up addr desc irq add", attempt(1));

	begin("a retry whose IRQ request fails with -ENXIO");
	SCRIPT(W.desc, -ETIMEDOUT);
	SCRIPT(W.irq, -ENXIO);
	probe();
	checki("two retries ran", 2, run_all());
	check("no free of the IRQ it didn't get, up after retry 2",
	      "state=UP irq=enabled req=1 free=0 add=1 destroy=0 up=3 down=2 wake=on work=idle bufs=1/0 bad=", snap());
	check("logged", "info: probe retry 2 succeeded, 10100 ms after the probe failed", log_find("probe retry"));
	check("retry 2 RESETs first (retry 1 read the descriptor)", "power_up reset msleep(100) addr desc irq add", attempt(2));
	begin("a retry whose IRQ is busy");
	SCRIPT(W.desc, -ETIMEDOUT);
	SCRIPT(W.irq, -EBUSY);
	probe();
	checki("gives up after it", 1, run_all());
	check("gave up, nothing held",
	      "state=GAVE_UP irq=free req=0 free=0 add=0 destroy=0 up=2 down=2 wake=on work=idle bufs=1/0 bad=", snap());
	check("logged as a warning", "warn: giving up after 1 probe retries in 5000 ms: -16", log_find("giving up"));

	begin("a retry whose power-up times out");
	SCRIPT(W.desc, -ETIMEDOUT);
	SCRIPT(W.power_up, 0, -ETIMEDOUT);
	probe();
	checki("two retries ran", 2, run_all());
	check("retry 1 stops at the power-up", "power_up", attempt(1));
	check("retry 2 probes", "power_up addr desc irq add", attempt(2));
	check("up", "state=UP irq=enabled req=1 free=0 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=", snap());
	check("retry 2 starts 5 s after retry 1 ended", "5000 12000 ", W.starts);
	begin("a retry whose power-up fails with -EIO");
	SCRIPT(W.desc, -ETIMEDOUT);
	SCRIPT(W.power_up, 0, -EIO);
	probe();
	checki("gives up after it", 1, run_all());
	check("logged", "warn: giving up after 1 probe retries in 5000 ms: -5", log_find("giving up"));
	check("gave up", "state=GAVE_UP irq=free req=0 free=0 add=0 destroy=0 up=1 down=1 wake=on work=idle bufs=1/0 bad=",
	      snap());

	begin("a retry whose descriptor read fails with -EIO");
	SCRIPT(W.desc, -ETIMEDOUT, -EIO);
	probe();
	checki("gives up after it", 1, run_all());
	check("logged", "warn: giving up after 1 probe retries in 5000 ms: -19", log_find("giving up"));
	check("no success", "", log_find("succeeded"));
	check("gave up", "state=GAVE_UP irq=free req=0 free=0 add=0 destroy=0 up=2 down=2 wake=on work=idle bufs=1/0 bad=",
	      snap());

	/* A descriptor was read (then hid add timed out): retries RESET first, to its register */
	begin("retries after a valid descriptor");
	SCRIPT(W.desc, 0, -ETIMEDOUT, 0, 0);
	SCRIPT(W.add, -ETIMEDOUT, -ETIMEDOUT, 0);
	checki("probe returns 0", 0, probe());
	checki("three retries ran", 3, run_all());
	check("RESET, a 100 ms settle, then the probe", "power_up reset msleep(100) addr desc power_down", attempt(1));
	check("hid add fails, the IRQ is freed", "power_up reset msleep(100) addr desc irq add free_irq power_down",
	      attempt(2));
	check("each RESET to the validated command register", "0022 0022 0022 ", W.resets);
	check("up", "state=UP irq=enabled req=3 free=2 add=1 destroy=0 up=4 down=3 wake=on work=idle bufs=1/0 bad=", snap());
	check("logged", "info: probe retry 3 succeeded, 17300 ms after the probe failed", log_find("probe retry"));
	begin("a RESET that fails");
	SCRIPT(W.desc, 0);
	SCRIPT(W.add, -ETIMEDOUT);
	SCRIPT(W.reset, -EIO);
	probe();
	run_all();
	check("the retry carries on", "power_up reset msleep(100) addr desc irq add", attempt(1));
	check("up", "state=UP irq=enabled req=2 free=1 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=", snap());

	begin("QTEC re-power-on times out after a retry added the hid");
	W.quirks = I2C_HID_QUIRK_RE_POWER_ON;
	SCRIPT(W.desc, -ETIMEDOUT);
	SCRIPT(W.set_power, -ETIMEDOUT);
	probe();
	checki("one retry ran", 1, run_all());
	check("up (the hid was added)",
	      "state=UP irq=enabled req=1 free=0 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=", snap());
	check("logged", "info: probe retry 1 succeeded, 5000 ms after the probe failed", log_find("probe retry"));
}

/* Each retry starts 5 s after the previous one ended, and none is queued past 120 s */
static void timing(void)
{
	char starts[2048] = "", delays[2048] = "";
	const unsigned long wrap = (unsigned long)-1 - msecs_to_jiffies(30000);

	for (unsigned int ms = 5000; ms <= 117000; ms += 7000)
		addf(starts, sizeof(starts), "%u ", ms);
	for (int i = 0; i < 17; i++)
		addf(delays, sizeof(delays), "5000 ");
	for (int w = 0; w < 2; w++) {
		begin("never answers, attempts of 2 s%s", w ? ", jiffies wrapping" : "");
		W.desc.dflt = -ETIMEDOUT;
		if (w)
			jiffies = wrap;
		probe();
		checki("17 retries", 17, run_all());
		check("each starts 5 s after the previous one ended", starts, W.starts);
		check("each queued for 5 s", delays, W.delays);
		check("logged as a warning", "warn: giving up after 17 probe retries in 119000 ms: -110", log_find("giving up"));
		check("gave up, nothing held",
		      "state=GAVE_UP irq=free req=0 free=0 add=0 destroy=0 up=18 down=18 wake=on work=idle bufs=1/0 bad=",
		      snap());
	}
}

static void cases_probe(void)
{
	stock_probe_failures();
	deferred_probes();
	retries();
	timing();
}
