# SPDX-License-Identifier: GPL-2.0-only
# The steps of scripts/install.sh that change the system: the temporary -proposed source,
# checked apt transactions, GRUB, the nvidia-persistenced override. Sourced by install.sh,
# whose settings (PROPOSED_*, GRUB_*, RELEASE, TMP) they use.
# shellcheck shell=bash

# Temporary <codename>-proposed at priority 1 (only versions asked for by name), as
# proart-p16-linux's install/lib.sh does; install.sh removes it again when it exits.
proposed_disable() { rm -f "$PROPOSED_SRC" "$PROPOSED_PIN"; }
proposed_enable() {
	local codename uri
	# shellcheck source=/dev/null
	codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
	uri=$(awk '/^URIs:/ {print $2; exit}' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true)
	printf 'Types: deb\nURIs: %s\nSuites: %s-proposed\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
		"${uri:-http://archive.ubuntu.com/ubuntu/}" "$codename" >"$PROPOSED_SRC"
	printf 'Package: *\nPin: release a=%s-proposed\nPin-Priority: 1\n' "$codename" >"$PROPOSED_PIN"
	apt-get update -q || warn "not every package source could be refreshed - continuing"
}

# apt_simulate ALLOWED BRANCH VERSION APT-ARGS...: runs apt-get -s APT-ARGS and stops, before
# anything is changed, unless apt can do it and does nothing apt_sim_check objects to.
apt_simulate() {
	local allowed=$1 branch=$2 version=$3 out problems
	shift 3
	if ! out=$(apt-get -s -q "$@" 2>&1); then
		printf '%s\n' "$out" >&2
		die "apt cannot do this (see above): nothing was changed"
	fi
	problems=$(apt_sim_check "$allowed" "$branch" "$version" <<<"$out") ||
		die "$(printf '%s; ' "$problems")stopping: nothing was changed"
}

grub_point() { # grub_point set-default|reboot KERNELRELEASE
	local id
	id=$(grub_entry_id "$GRUB_CFG" "$2") || die "no GRUB entry for $2 in $GRUB_CFG"
	"grub-$1" "$id"
	msg "grub-$1 $id"
}

# Before anything changes: /etc/default/grub must be editable as install.sh edits it, and no
# /etc/default/grub.d/*.cfg may override what it sets there.
grub_preflight() {
	local v over
	grub_default_get "$GRUB_FILE" >/dev/null || die "cannot edit GRUB_CMDLINE_LINUX_DEFAULT in $GRUB_FILE (see above)"
	grub_var_get "$GRUB_FILE" GRUB_DEFAULT >/dev/null || die "cannot edit GRUB_DEFAULT in $GRUB_FILE (see above)"
	for v in GRUB_CMDLINE_LINUX_DEFAULT GRUB_DEFAULT; do
		over=$(grub_dropin_overrides "$GRUB_DROPINS" "$v")
		[[ -z $over ]] || die "$GRUB_DROPINS sets $v after $GRUB_FILE, so editing $GRUB_FILE would not reach grub.cfg: $over"
	done
}

# After update-grub: grub.cfg must boot RELEASE with the USB4 options and honour saved_entry.
grub_verify() {
	local args
	args=$(grub_linux_args "$GRUB_CFG" "$RELEASE") || die "no GRUB entry for $RELEASE in $GRUB_CFG"
	cmdline_has_pci "$args" || die "$GRUB_CFG boots $RELEASE without ${N1X_PCI_OPTS[*]}: $args"
	# shellcheck disable=SC2016 # literal grub.cfg text
	grep -qF 'set default="${saved_entry}"' "$GRUB_CFG" ||
		die "$GRUB_CFG does not boot saved_entry (GRUB_DEFAULT=saved has no effect)"
}

# saved_entry in grubenv: GRUB's default when GRUB_DEFAULT=saved.
grub_saved_entry() { grub-editenv - list 2>/dev/null | sed -n 's/^saved_entry=//p'; }

# grub_default_is KERNELRELEASE: true if saved_entry is that kernel's entry (in grub.cfg).
grub_default_is() {
	local id
	id=$(grub_entry_id "$GRUB_CFG" "$1" 2>/dev/null) && [[ $(grub_saved_entry) == "$id" ]]
}

# grub_keep_fallback PREV: run before any package changes, so that a failure anywhere after it
# leaves PREV booting. The kernel package's own update-grub makes the new kernel entry 0, which
# GRUB_DEFAULT=0 (stock Ubuntu) would boot; with GRUB_DEFAULT=saved (which grub-set-default and
# grub-reboot need; --remove restores the old value) and saved_entry on PREV it can't. A RELEASE
# made the default with --default stays the default.
grub_keep_fallback() {
	local was
	was=$(grub_use_saved "$GRUB_FILE") || die "cannot edit GRUB_DEFAULT in $GRUB_FILE"
	[[ -z $was ]] || msg "GRUB_DEFAULT=saved (was: $was), so GRUB keeps its default and the fallback boot works"
	update-grub || die "update-grub failed (see above); fix that and run install.sh again"
	grub_default_is "$RELEASE" || grub_point set-default "$1"
}

# Writes (or refreshes) the nvidia-persistenced override when the packaged unit has the
# ordering cycle, and drops ours when it no longer does. An override someone else wrote stays.
persistenced_apply() {
	if ! persistenced_override "$PERSISTENCED_UNIT" >"$TMP/persistenced"; then
		persistenced_drop
		return 0
	fi
	if [[ -e $PERSISTENCED_OVERRIDE ]] && ! persistenced_is_ours "$PERSISTENCED_OVERRIDE"; then
		warn "$PERSISTENCED_OVERRIDE was not written by install.sh, so it stays as it is. If it is the packaged unit without $PERSISTENCED_CYCLE, delete it and run install.sh again, which then keeps it in step with the package."
		return 0
	fi
	cmp -s "$TMP/persistenced" "$PERSISTENCED_OVERRIDE" && return 0
	cp "$TMP/persistenced" "$PERSISTENCED_OVERRIDE.n1x"
	chmod 644 "$PERSISTENCED_OVERRIDE.n1x"
	mv "$PERSISTENCED_OVERRIDE.n1x" "$PERSISTENCED_OVERRIDE"
	systemctl daemon-reload
	msg "Wrote $PERSISTENCED_OVERRIDE: $PERSISTENCED_UNIT without its ordering cycle ($PERSISTENCED_CYCLE)"
}

persistenced_drop() {
	persistenced_is_ours "$PERSISTENCED_OVERRIDE" || return 0
	rm -f "$PERSISTENCED_OVERRIDE"
	systemctl daemon-reload
	msg "Removed $PERSISTENCED_OVERRIDE"
}
