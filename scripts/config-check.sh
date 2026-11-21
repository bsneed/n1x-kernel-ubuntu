#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - check that every option of a config fragment survived olddefconfig
#
# Why: Kconfig silently drops or changes an option whose dependencies are not met, so a
# fragment line can be a no-op without any error. This fails the build instead.
# Remove: nothing to remove; it only reads.
# Run with: bash scripts/config-check.sh FRAGMENT DOTCONFIG
set -euo pipefail

[[ $# -eq 2 ]] || {
	echo "usage: $0 FRAGMENT DOTCONFIG" >&2
	exit 2
}
fragment=$1 config=$2
[[ -r $fragment ]] || { echo "ERROR: cannot read $fragment" >&2; exit 2; }
[[ -r $config ]] || { echo "ERROR: cannot read $config" >&2; exit 2; }

# Final value of each symbol: "y", "m", a string/number, or "n" for "is not set"/absent.
declare -A have
while IFS= read -r line; do
	if [[ $line =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*)$ ]]; then
		have[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
	elif [[ $line =~ ^#\ (CONFIG_[A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
		have[${BASH_REMATCH[1]}]=n
	fi
done <"$config"

bad=0 checked=0
while IFS= read -r line; do
	if [[ $line =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*)$ ]]; then
		sym=${BASH_REMATCH[1]} want=${BASH_REMATCH[2]}
	elif [[ $line =~ ^#\ (CONFIG_[A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
		sym=${BASH_REMATCH[1]} want=n
	else
		continue
	fi
	checked=$((checked + 1))
	got=${have[$sym]:-n}
	if [[ $got != "$want" ]]; then
		echo "config: $sym wanted '$want', got '$got'" >&2
		bad=$((bad + 1))
	fi
done <"$fragment"

if [[ $checked -eq 0 ]]; then
	echo "ERROR: $fragment sets no options" >&2
	exit 1
fi
if [[ $bad -gt 0 ]]; then
	echo "ERROR: $bad of $checked options in $fragment did not survive olddefconfig" >&2
	exit 1
fi
echo "config: all $checked options in ${fragment##*/} are set"
