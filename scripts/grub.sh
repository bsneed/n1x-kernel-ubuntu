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

# _pci_unmerge OPTS: prints OPTS without the options equal to one of N1X_PCI_OPTS.
_pci_unmerge() {
	local -a have=() out=()
	local h w drop
	[[ -n $1 ]] && IFS=, read -ra have <<<"$1"
	for h in "${have[@]}"; do
		drop=0
		for w in "${N1X_PCI_OPTS[@]}"; do [[ $h == "$w" ]] && drop=1; done
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

# cmdline_remove_pci VALUE: undoes cmdline_add_pci in every pci= parameter. A pci= left
# empty is dropped; options someone else set stay.
cmdline_remove_pci() {
	local -a WORDS out=()
	local w opts
	_words "$1"
	for w in "${WORDS[@]}"; do
		if [[ $w == pci=* ]]; then
			opts=$(_pci_unmerge "${w#pci=}")
			[[ -n $opts ]] || continue
			w=pci=$opts
		fi
		out+=("$w")
	done
	WORDS=("${out[@]}")
	_join
}

# grub_default_get FILE: prints GRUB_CMDLINE_LINUX_DEFAULT's value from an /etc/default/grub
# style FILE (empty if unset). Fails if the line is not a plain double-quoted assignment.
grub_default_get() {
	local file=$1 line re='^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"[[:space:]]*$'
	[[ -f $file ]] || { echo "no such file: $file" >&2; return 1; }
	line=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$file" | tail -1) || true
	[[ -z $line ]] && return 0
	[[ $line =~ $re ]] || { echo "$file: unsupported GRUB_CMDLINE_LINUX_DEFAULT line: $line" >&2; return 1; }
	printf '%s\n' "${BASH_REMATCH[1]}"
}

# grub_default_set FILE VALUE: sets GRUB_CMDLINE_LINUX_DEFAULT="VALUE" in FILE, replacing the
# last assignment (or appending one). Writes a new file and renames it over the old one.
grub_default_set() {
	local file=$1 value=$2 tmp
	[[ -f $file ]] || { echo "no such file: $file" >&2; return 1; }
	tmp=$(mktemp "$file.XXXXXX")
	N1X_GRUB_VALUE=$value awk '
		BEGIN { v = ENVIRON["N1X_GRUB_VALUE"] }
		{ lines[NR] = $0 }
		/^GRUB_CMDLINE_LINUX_DEFAULT=/ { last = NR }
		END {
			for (i = 1; i <= NR; i++) print (i == last ? "GRUB_CMDLINE_LINUX_DEFAULT=\"" v "\"" : lines[i])
			if (!last) print "GRUB_CMDLINE_LINUX_DEFAULT=\"" v "\""
		}' "$file" >"$tmp"
	chmod --reference="$file" "$tmp" 2>/dev/null || chmod 644 "$tmp"
	mv "$tmp" "$file"
}

# grub_entry_id GRUBCFG KERNELRELEASE: the "<submenu id>><entry id>" of that kernel's normal
# (not recovery) entry in grub.cfg, as grub-reboot and grub-set-default take it.
grub_entry_id() {
	local cfg=$1 krel=$2
	[[ -r $cfg ]] || { echo "cannot read $cfg" >&2; return 1; }
	awk -v k="$krel" '
		function id(line,   s) {
			s = line; sub(/.*\$menuentry_id_option '\''/, "", s); sub(/'\''.*/, "", s); return s
		}
		/^[[:space:]]*submenu / && index($0, "$menuentry_id_option") { sub_id = id($0) }
		/^[[:space:]]*menuentry / && index($0, "$menuentry_id_option") {
			e = id($0)
			if (index(e, "gnulinux-" k "-advanced-") == 1 && sub_id != "") { print sub_id ">" e; found = 1; exit }
		}
		END { exit !found }' "$cfg"
}
