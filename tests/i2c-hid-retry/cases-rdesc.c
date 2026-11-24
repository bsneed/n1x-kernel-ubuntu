// SPDX-License-Identifier: GPL-2.0-only
/*
 * n1x-kernel-ubuntu - harness.c's scenarios of report descriptors that a device not yet ready
 * sends (cut short, zeros, unbalanced): 0002's check of them, the retry they lead to on a P16,
 * and stock's behaviour elsewhere. Included by harness.c.
 */

#define REJECTED_LOG "err: report descriptor rejected (unbalanced collection, 33 bytes)"

/* 0002's check against each descriptor, against hid-core's verdict, and on every cut of a valid one */
static void rdesc_check(void)
{
	char what[64];
	const char *why;
	bool all = true;

	begin("the report descriptor check");
	for (int i = 0; i < RD_N; i++) {
		const struct fake_rdesc *r = &fake_rdescs[i];

		why = i2c_hid_probe_retry_check_rdesc(r->b, RDESC_LEN);
		snprintf(what, sizeof(what), "%s: what is wrong", r->name);
		check(what, r->why ? r->why : "(passes)", why ? why : "(passes)");
		/* Stricter than hid-core only on a descriptor without a collection, which nothing can use */
		snprintf(what, sizeof(what), "%s: as hid-core, but for zeros", r->name);
		checki(what, i == RD_ZEROS ? !r->core_rejects : r->core_rejects, why != NULL);
	}
	for (unsigned int n = 1; n < RDESC_LEN; n++)
		all = all && i2c_hid_probe_retry_check_rdesc(fake_rdescs[RD_VALID].b, n);
	checki("every cut of the valid one is rejected", 1, all);
	check("the valid one's first 32 bytes: its collection is open", "unbalanced collection",
	      i2c_hid_probe_retry_check_rdesc(fake_rdescs[RD_VALID].b, RDESC_LEN - 1));
	check("its first 18 bytes: its 4-byte item doesn't fit", "item past the end",
	      i2c_hid_probe_retry_check_rdesc(fake_rdescs[RD_VALID].b, 18));
	check("its first 4 bytes: no collection", "no collection",
	      i2c_hid_probe_retry_check_rdesc(fake_rdescs[RD_VALID].b, 4));
}

/* What ASTH0001 did: a descriptor cut short on the probe, a valid one on the retry */
static void rdesc_retry(void)
{
	static const char *const machines[] = { "ProArt P16 H7607BA", "XPS 13 9345" };

	for (int valid = RD_VALID; valid <= RD_NESTED; valid++) {
		begin("P16, a valid report descriptor (%s)", fake_rdescs[valid].name);
		SCRIPT(W.rdesc, valid);
		checki("probe returns 0", 0, probe());
		check("up as stock",
		      "state=NONE irq=enabled req=1 free=0 add=1 destroy=0 up=1 down=0 wake=on work=idle bufs=1/0 bad=", snap());
		checki("a driver bound", 1, W.bound);
		checki("the descriptor passed on as read", 0, memcmp(ih()->hid->dev_rdesc, fake_rdescs[valid].b, RDESC_LEN));
		check("nothing logged", "", W.log);
	}

	begin("P16, a report descriptor cut short, then a valid one");
	SCRIPT(W.rdesc, RD_CUT);
	checki("probe returns 0", 0, probe());
	check("deferred, its IRQ freed, the hid not added",
	      "state=PENDING irq=free req=1 free=1 add=0 destroy=0 up=1 down=1 wake=off work=queued bufs=1/0 bad=", snap());
	checki("the bad descriptor not kept", 1, ih()->hid->dev_rdesc == NULL);
	check("logged", REJECTED_LOG "|err: can't add hid device: -74|"
	      "info: probe failed (-74), retrying every 5 s for up to 300 s|", W.log);
	checki("one retry ran", 1, run_all());
	check("it RESETs, then probes", "power_up reset msleep(100) addr desc irq add", attempt(1));
	check("up",
	      "state=UP irq=enabled req=2 free=1 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=", snap());
	checki("a driver bound", 1, W.bound);
	checki("two descriptor reads", 2, W.rdesc_reads);
	check("logged", "info: probe retry 1 succeeded, 5100 ms after the probe failed", log_find("probe retry"));
	do_remove();
	check("remove releases everything once",
	      "state=UP irq=free req=2 free=2 add=1 destroy=1 up=2 down=2 wake=on work=idle bufs=1/1 bad=", snap());

	begin("P16, a descriptor timeout, then zeros, then a valid report descriptor");
	SCRIPT(W.desc, -ETIMEDOUT);
	SCRIPT(W.rdesc, RD_ZEROS, RD_VALID);
	probe();
	checki("two retries ran", 2, run_all());
	check("retry 1 rejects its descriptor", "power_up addr desc irq add free_irq power_down", attempt(1));
	check("retry 2 RESETs first", "power_up reset msleep(100) addr desc irq add", attempt(2));
	check("logged", "err: failed to fetch HID descriptor: -110|err: Failed to fetch the HID Descriptor|"
	      "info: probe failed (-110), retrying every 5 s for up to 300 s|"
	      "err: report descriptor rejected (no collection, 33 bytes)|err: can't add hid device: -74|"
	      "info: probe retry 1 read a bad report descriptor, retrying|"
	      "info: probe retry 2 succeeded, 10100 ms after the probe failed|", W.log);
	check("up after retry 2",
	      "state=UP irq=enabled req=2 free=1 add=1 destroy=0 up=3 down=2 wake=on work=idle bufs=1/0 bad=", snap());
	check("the next retry 5 s after retry 1 started", "5000 5000 ", W.delays);

	for (int i = RD_CUT; i < RD_N; i++) {
		if (i == RD_ZEROS)
			continue;
		begin("P16, %s, then valid", fake_rdescs[i].name);
		SCRIPT(W.rdesc, i);
		probe();
		check("deferred", "PENDING", state_name());
		checki("one retry ran", 1, run_all());
		check("up", "UP", state_name());
		check("no misuse", "", W.bad);
	}

	for (int m = 0; m < 2; m++) {
		begin("%s, only report descriptors cut short", m ? "not a P16" : "P16");
		W.product = machines[m];
		W.rdesc.dflt = RD_CUT;
		checki("probe returns 0", 0, probe());
		if (m) {
			check("added as stock, no driver",
			      "state=NONE irq=enabled req=1 free=0 add=1 destroy=0 up=1 down=0 wake=on work=idle bufs=1/0 bad=",
			      snap());
			checki("no driver bound", 0, W.bound);
			check("hid-generic's probe failed; no check, no retry",
			      "err: probe with driver hid-generic failed with error -22|", W.log);
			checki("no retry", 0, run_all());
			continue;
		}
		checki("60 retries", 60, run_all());
		check("gave up, nothing held",
		      "state=GAVE_UP irq=free req=61 free=61 add=0 destroy=0 up=61 down=61 wake=off work=idle bufs=1/0 bad=",
		      snap());
		checki("no driver bound", 0, W.bound);
		check("logged", "warn: giving up after 60 probe retries in 300100 ms: -74", log_find("giving up"));
		checki("each failed retry but the last logged", 59, count_lines("read a bad report descriptor, retrying"));
		checki("each rejection logged", 61, count_lines(REJECTED_LOG));
		/* The recovery by hand: unbind (remove), then bind (probe) */
		do_remove();
		check("unbind releases everything once",
		      "state=GAVE_UP irq=free req=61 free=61 add=0 destroy=1 up=61 down=61 wake=off work=idle bufs=1/1 bad=",
		      snap());
		W.rdesc.dflt = RD_VALID;
		checki("bind probes again", 0, probe());
		check("up", "NONE", state_name());
		checki("a driver bound", 1, W.bound);
	}

	begin("not a P16, zeros");
	W.vendor = "Dell Inc.";
	SCRIPT(W.rdesc, RD_ZEROS);
	checki("probe returns 0", 0, probe());
	check("added as stock",
	      "state=NONE irq=enabled req=1 free=0 add=1 destroy=0 up=1 down=0 wake=on work=idle bufs=1/0 bad=", snap());
	checki("hid-generic binds it (hid-core accepts zeros)", 1, W.bound);
	check("nothing logged", "", W.log);
}

static void cases_rdesc(void)
{
	rdesc_check();
	rdesc_retry();
}
