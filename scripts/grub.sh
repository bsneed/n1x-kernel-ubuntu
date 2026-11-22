# SPDX-License-Identifier: GPL-2.0-only
# GRUB helpers for scripts/install.sh: kernel command line edits and menu entry ids.
# Sourced, not run. The string functions have no side effects; tests/run.sh covers them.
# shellcheck shell=bash

# PCI hotplug padding the N1x USB4 tunnel root ports need for a dock's PCIe switch (bus numbers
# and MMIO windows); Omarchy's install/hardware/n1x.sh values for the ProArt P14 and P16.
N1X_PCI_OPTS=(hpbussize=0x80 hpmmiosize=32M hpmmioprefsize=32G)

# _pci_merge OPTS: OPTS is a pci= value ("a,b=1"). Prints it with N1X_PCI_OPTS set: an option
# with the same name but another value is replaced, a missing one appended, the rest kept.
_pci_merge() {
	local -a have=() out=()
	local want key h replaced
	[[ -n $1 ]] && IFS=, read -ra have <<<"$1"
	out=("${have[@]}")
	for want in "${N1X_PCI_OPTS[@]}"; do
		key=${want%%=*} replaced=0
		for h in "${!out[@]}"; do
			if [[ ${out[h]%%=*} == "$key" ]]; then
				out[h]=$want replaced=1
			fi
		done
		[[ $replaced -eq 1 ]] || out+=("$want")
	done
	local IFS=,
	printf '%s\n' "${out[*]}"
}

# _pci_unmerge OPTS [BEFORE]: prints OPTS without N1X_PCI_OPTS. BEFORE is the user's own
# pci= options from before the install (comma-separated): one of ours that was there already
# stays, and one that replaced the user's value for the same option gets that value back.
_pci_unmerge() {
	local -a have=() before=() out=()
	local h w b drop
	[[ -n $1 ]] && IFS=, read -ra have <<<"$1"
	[[ -n ${2:-} ]] && IFS=, read -ra before <<<"$2"
	for h in "${have[@]}"; do
		drop=0
		for w in "${N1X_PCI_OPTS[@]}"; do [[ $h == "$w" ]] && drop=1; done
		if [[ $drop -eq 1 ]]; then
			for b in "${before[@]}"; do
				[[ ${b%%=*} == "${h%%=*}" ]] && { h=$b drop=0; }
			done
		fi
		[[ $drop -eq 1 ]] || out+=("$h")
	done
	local IFS=,
	printf '%s\n' "${out[*]}"
}

# _words VALUE: VALUE split at single spaces into the array WORDS (runs of spaces give empty
# words, so joining WORDS with one space gives VALUE back unchanged).
_words() {
	WORDS=()
	[[ -n $1 ]] && mapfile -d ' ' -t WORDS < <(printf '%s' "$1")
	return 0
}

# _join: prints WORDS joined with single spaces.
_join() {
	local IFS=' '
	printf '%s\n' "${WORDS[*]}"
}

# cmdline_add_pci VALUE: a kernel command line (as GRUB_CMDLINE_LINUX_DEFAULT holds it) with
# N1X_PCI_OPTS in its pci= parameter. The last pci= is edited (the kernel applies them in
# order, so the last one wins); without one, a new pci= is appended. Idempotent.
cmdline_add_pci() {
	local -a WORDS
	local i last=-1
	_words "$1"
	for i in "${!WORDS[@]}"; do [[ ${WORDS[i]} == pci=* ]] && last=$i; done
	if [[ $last -ge 0 ]]; then
		WORDS[last]=pci=$(_pci_merge "${WORDS[last]#pci=}")
	elif [[ -z ${1//[[:space:]]/} ]]; then
		WORDS=("pci=$(_pci_merge "")")
	else
		WORDS+=("pci=$(_pci_merge "")")
	fi
	_join
}

# cmdline_remove_pci VALUE [BEFORE]: undoes cmdline_add_pci in every pci= parameter. A pci=
# left empty is dropped; options someone else set stay. BEFORE is the command line from before
# the install: if VALUE is still exactly what the install made of it, BEFORE comes back as it
# was; otherwise only our options go, and a value of the user's that we replaced is restored.
cmdline_remove_pci() {
	local -a WORDS out=()
	local w opts prev_opts=""
	if [[ $# -ge 2 ]]; then
		[[ $1 == "$(cmdline_add_pci "$2")" ]] && { printf '%s\n' "$2"; return 0; }
		_words "$2"
		for w in "${WORDS[@]}"; do [[ $w == pci=* ]] && prev_opts+=${prev_opts:+,}${w#pci=}; done
	fi
	_words "$1"
	for w in "${WORDS[@]}"; do
		if [[ $w == pci=* ]]; then
			opts=$(_pci_unmerge "${w#pci=}" "$prev_opts")
			[[ -n $opts ]] || continue
			w=pci=$opts
		fi
		out+=("$w")
	done
	WORDS=("${out[@]}")
	_join
}

# cmdline_has_pci VALUE: true if every one of N1X_PCI_OPTS is in a pci= parameter of VALUE.
cmdline_has_pci() {
	local -a WORDS opts have=()
	local w o
	_words "$1"
	for w in "${WORDS[@]}"; do
		[[ $w == pci=* ]] || continue
		IFS=, read -ra opts <<<"${w#pci=}"
		have+=("${opts[@]}")
	done
	for o in "${N1X_PCI_OPTS[@]}"; do
		[[ ${#have[@]} -gt 0 ]] && printf '%s\n' "${have[@]}" | grep -qxF -- "$o" || return 1
	done
}

# grub_var_line FILE VAR: the last assignment of VAR in an /etc/default/grub style FILE, as
# the whole line (empty if VAR is not set). Fails if VAR is assigned in any other form
# (indented, export, ...): grub-mkconfig would still honour that line, so editing only the
# plain ones could silently lose to it.
grub_var_line() {
	local file=$1 var=$2 line
	[[ -f $file ]] || { echo "no such file: $file" >&2; return 1; }
	while IFS= read -r line; do
		[[ $line == "$var="* ]] || { echo "$file: unsupported $var line: $line" >&2; return 1; }
	done < <(grep -E "^[[:space:]]*(export[[:space:]]+)?$var=" "$file" || true)
	grep -E "^$var=" "$file" | tail -1 || true
}

# grub_var_get FILE VAR: the value of VAR (quotes removed) from grub_var_line. Takes
# VAR=value, VAR="value" and VAR='value'; fails on anything the shell would expand.
grub_var_get() {
	local line v
	line=$(grub_var_line "$1" "$2") || return 1
	[[ -z $line ]] && return 0
	v=${line#"$2"=}
	if [[ $v =~ ^\"([^\"\$\`\\]*)\"[[:space:]]*$ || $v =~ ^\'([^\']*)\'[[:space:]]*$ ||
		$v =~ ^([^[:space:]\"\'\$\`\\]*)[[:space:]]*$ ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
	else
		echo "$1: unsupported $2 line: $line" >&2
		return 1
	fi
}

# grub_default_get FILE: prints GRUB_CMDLINE_LINUX_DEFAULT's value from an /etc/default/grub
# style FILE (empty if unset). Fails if the line is not a plain double-quoted assignment.
grub_default_get() {
	local file=$1 line re='^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"[[:space:]]*$'
	line=$(grub_var_line "$file" GRUB_CMDLINE_LINUX_DEFAULT) || return 1
	[[ -z $line ]] && return 0
	[[ $line =~ $re ]] || { echo "$file: unsupported GRUB_CMDLINE_LINUX_DEFAULT line: $line" >&2; return 1; }
	printf '%s\n' "${BASH_REMATCH[1]}"
}

# grub_line_set FILE VAR LINE: replaces the last assignment of VAR in FILE with LINE (appends
# LINE if VAR is not set; an empty LINE deletes the assignment). Writes a new file and renames
# it over the old one.
grub_line_set() {
	local file=$1 tmp
	[[ -f $file ]] || { echo "no such file: $file" >&2; return 1; }
	tmp=$(mktemp "$file.XXXXXX")
	N1X_GRUB_VAR=$2= N1X_GRUB_LINE=$3 awk '
		BEGIN { v = ENVIRON["N1X_GRUB_VAR"]; l = ENVIRON["N1X_GRUB_LINE"] }
		{ lines[NR] = $0 }
		index($0, v) == 1 { last = NR }
		END {
			for (i = 1; i <= NR; i++)
				if (i != last) print lines[i]; else if (l != "") print l
			if (!last && l != "") print l
		}' "$file" >"$tmp"
	chmod --reference="$file" "$tmp" 2>/dev/null || chmod 644 "$tmp"
	mv "$tmp" "$file"
}

# grub_default_set FILE VALUE: sets GRUB_CMDLINE_LINUX_DEFAULT="VALUE" in FILE (grub_line_set).
grub_default_set() {
	grub_line_set "$1" GRUB_CMDLINE_LINUX_DEFAULT "GRUB_CMDLINE_LINUX_DEFAULT=\"$2\""
}

# grub_dropin_overrides DIR VAR: prints "file: line" for each assignment of VAR in DIR/*.cfg
# (/etc/default/grub.d, sourced after /etc/default/grub) that replaces the value instead of
# extending it ("$VAR ..."), so an edit of /etc/default/grub would not reach grub.cfg.
grub_dropin_overrides() {
	local f line
	for f in "$1"/*.cfg; do
		[[ -f $f ]] || continue
		while IFS= read -r line; do
			[[ $line == *"\$$2"* || $line == *"\${$2"* ]] || printf '%s: %s\n' "$f" "$line"
		done < <(grep -E "^[[:space:]]*(export[[:space:]]+)?$2=" "$f" || true)
	done
}

# grub_entry_id GRUBCFG KERNELRELEASE: the id of that kernel's normal (not recovery) entry in
# grub.cfg, as grub-reboot and grub-set-default take it: "<submenu id>><entry id>" inside
# Ubuntu's "Advanced options" submenu, or the entry id alone with GRUB_DISABLE_SUBMENU=y.
grub_entry_id() {
	local cfg=$1 krel=$2
	[[ -r $cfg ]] || { echo "cannot read $cfg" >&2; return 1; }
	awk -v k="$krel" '
		function id(line,   s) {
			s = line; sub(/.*\$menuentry_id_option '\''/, "", s); sub(/'\''.*/, "", s); return s
		}
		/^[[:space:]]*submenu / && index($0, "$menuentry_id_option") { sub_id = id($0); sub_depth = depth + 1 }
		/^[[:space:]]*menuentry / && index($0, "$menuentry_id_option") {
			e = id($0)
			if (index(e, "gnulinux-" k "-advanced-") == 1) {
				print (sub_id != "" ? sub_id ">" e : e); found = 1; exit
			}
		}
		/\{[[:space:]]*$/ { depth++ }
		/^[[:space:]]*\}[[:space:]]*$/ { if (depth == sub_depth) sub_id = ""; depth-- }
		END { exit !found }' "$cfg"
}

# grub_linux_args GRUBCFG KERNELRELEASE: the linux line of that kernel's normal entry, which
# holds the command line grub-mkconfig wrote for it.
grub_linux_args() {
	local cfg=$1 krel=$2
	[[ -r $cfg ]] || { echo "cannot read $cfg" >&2; return 1; }
	awk -v k="$krel" '
		/^[[:space:]]*menuentry / { inside = index($0, "'\''gnulinux-" k "-advanced-") > 0 }
		inside && /^[[:space:]]*linux[[:space:]]/ { print; found = 1; exit }
		END { exit !found }' "$cfg"
}

# grub_use_saved FILE: sets GRUB_DEFAULT=saved in FILE, which grub-set-default and grub-reboot
# need (with GRUB_DEFAULT=0, Ubuntu's default, GRUB boots the newest kernel whatever they say).
# Prints the value it replaced ("" if it was unset); prints nothing if it was saved already.
grub_use_saved() {
	local v line
	v=$(grub_var_get "$1" GRUB_DEFAULT) || return 1
	[[ $v == saved ]] && return 0
	line=$(grub_var_line "$1" GRUB_DEFAULT)
	grub_line_set "$1" GRUB_DEFAULT GRUB_DEFAULT=saved
	printf '%s\n' "${line:-GRUB_DEFAULT unset}"
}

# grub_restore_default FILE BEFORE: undoes grub_use_saved. If FILE still has GRUB_DEFAULT=saved
# and the copy BEFORE (taken at the first install) had something else, that line comes back
# (or none, if BEFORE had none). A GRUB_DEFAULT changed since then stays.
grub_restore_default() {
	local before
	[[ $(grub_var_get "$1" GRUB_DEFAULT) == saved ]] || return 0
	before=$(grub_var_line "$2" GRUB_DEFAULT) || return 1
	[[ $(grub_var_get "$2" GRUB_DEFAULT) == saved ]] && return 0
	grub_line_set "$1" GRUB_DEFAULT "$before"
}
