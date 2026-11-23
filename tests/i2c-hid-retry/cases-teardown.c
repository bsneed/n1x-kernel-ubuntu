// SPDX-License-Identifier: GPL-2.0-only
/*
 * n1x-kernel-ubuntu - harness.c's scenarios of remove, shutdown and system sleep (suspend and
 * resume, freeze and restore) in each state of the retry. Included by harness.c.
 */

enum { S_NONE, S_PENDING, S_UP, S_GAVE_UP };
static const char *const S[] = { "NONE", "PENDING", "UP", "GAVE_UP" };

/* NONE: probe worked. PENDING: 2 s after a failed probe. UP: retry 1 worked. GAVE_UP: it failed. */
static void make(int s, const char *what)
{
	begin("%s in %s", what, S[s]);
	if (s == S_PENDING || s == S_UP)
		SCRIPT(W.desc, -ETIMEDOUT);
	if (s == S_GAVE_UP)
		SCRIPT(W.desc, -ETIMEDOUT, -EIO);
	probe();
	if (s == S_UP || s == S_GAVE_UP)
		run_all();
	if (s == S_PENDING)
		advance_ms(2000);
	check("set up", S[s], state_name());
}

static void removes(void)
{
	static const char *const after[] = {
		"state=NONE irq=free req=1 free=1 add=1 destroy=1 up=1 down=1 wake=on work=idle bufs=1/1 bad=",
		"state=PENDING irq=free req=0 free=0 add=0 destroy=1 up=1 down=1 wake=on work=idle bufs=1/1 bad=",
		"state=UP irq=free req=1 free=1 add=1 destroy=1 up=2 down=2 wake=on work=idle bufs=1/1 bad=",
		"state=GAVE_UP irq=free req=0 free=0 add=0 destroy=1 up=2 down=2 wake=on work=idle bufs=1/1 bad=",
	};

	for (int s = S_NONE; s <= S_GAVE_UP; s++) {
		make(s, "remove");
		do_remove();
		check("everything released once", after[s], snap());
		check("stock's suspend only when up", s == S_NONE || s == S_UP ?
		      "suspend=1/1 resume=0 set_power=0 tail=0 restore=0" :
		      "suspend=0/0 resume=0 set_power=0 tail=0 restore=0", calls());
		checki("no retry runs after it", 0, run_all());
	}
}

static void shutdowns(void)
{
	static const char *const after[] = {
		"state=NONE irq=free req=1 free=1 add=1 destroy=0 up=1 down=0 wake=on work=idle bufs=1/0 bad=",
		"state=PENDING irq=free req=0 free=0 add=0 destroy=0 up=1 down=1 wake=on work=idle bufs=1/0 bad=",
		"state=UP irq=free req=1 free=1 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=",
		"state=GAVE_UP irq=free req=0 free=0 add=0 destroy=0 up=2 down=2 wake=on work=idle bufs=1/0 bad=",
	};

	for (int s = S_NONE; s <= S_GAVE_UP; s++) {
		make(s, "shutdown");
		do_shutdown();
		check("the IRQ freed only if it was requested", after[s], snap());
		check("SET_POWER and shutdown_tail only when up", s == S_NONE || s == S_UP ?
		      "suspend=0/0 resume=0 set_power=1 tail=1 restore=0" :
		      "suspend=0/0 resume=0 set_power=0 tail=0 restore=0", calls());
		checki("no retry runs after it", 0, run_all());
	}
}

static void system_sleep(void)
{
	static const char *const asleep[] = {
		"state=NONE irq=disabled req=1 free=0 add=1 destroy=0 up=1 down=0 wake=on work=idle bufs=1/0 bad=",
		"state=PENDING irq=free req=0 free=0 add=0 destroy=0 up=1 down=1 wake=on work=idle bufs=1/0 bad=",
		"state=UP irq=disabled req=1 free=0 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=",
		"state=GAVE_UP irq=free req=0 free=0 add=0 destroy=0 up=2 down=2 wake=on work=idle bufs=1/0 bad=",
	};
	static const char *const awake[] = {
		"state=NONE irq=enabled req=1 free=0 add=1 destroy=0 up=1 down=0 wake=on work=idle bufs=1/0 bad=",
		"state=PENDING irq=free req=0 free=0 add=0 destroy=0 up=1 down=1 wake=on work=queued bufs=1/0 bad=",
		"state=UP irq=enabled req=1 free=0 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=",
		"state=GAVE_UP irq=free req=0 free=0 add=0 destroy=0 up=2 down=2 wake=on work=idle bufs=1/0 bad=",
	};
	char want[160];

	for (int restore = 0; restore < 2; restore++) {
		for (int s = S_NONE; s <= S_GAVE_UP; s++) {
			bool up = s == S_NONE || s == S_UP;

			make(s, restore ? "freeze and restore" : "suspend and resume");
			checki("suspend returns 0", 0, pm_suspend());
			check("asleep", asleep[s], snap());
			advance_ms(60000);
			checki(restore ? "restore returns 0" : "resume returns 0", 0, restore ? pm_restore() : pm_resume());
			check("awake", awake[s], snap());
			snprintf(want, sizeof(want), "suspend=%d/0 resume=%d set_power=0 tail=0 restore=%d", up, up,
				 up && restore);
			check("stock's sleep callbacks only when up", want, calls());
			check("queued again only while pending", s == S_NONE ? "" : s == S_PENDING ? "5000 5000 " : "5000 ",
			      W.delays);
		}
	}

	/* The retry starts again 5 s after the resume */
	begin("suspend 2 s into a pending retry");
	SCRIPT(W.desc, -ETIMEDOUT);
	probe();
	advance_ms(2000);
	pm_suspend();
	pm_resume();
	check("queued for 5 s", "5000 5000 ", W.delays);
	checki("one retry ran", 1, run_all());
	check("it started 7 s after the failure", "7000 ", W.starts);
	check("up", "state=UP irq=enabled req=1 free=0 add=1 destroy=0 up=2 down=1 wake=on work=idle bufs=1/0 bad=", snap());
}

static void cases_teardown(void)
{
	removes();
	shutdowns();
	system_sleep();
}
