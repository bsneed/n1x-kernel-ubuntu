#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - tests of the helpers in scripts/ (tests/t-*.sh)
#
# Why: scripts/install.sh edits /etc/default/grub, picks GRUB entries and NVIDIA packages and
# drives apt with these helpers, and scripts/build.sh reads Omarchy's recipe with them; a mistake
# there leaves a laptop booting the wrong kernel, without a GPU driver or the USB4 parameters.
# Remove: nothing to remove; it only uses a temporary directory.
# Run with: bash tests/run.sh   (bash 4.4 or newer)
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh
. scripts/grub.sh

pass=0 failed=0 skipped=0
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

eq() { # eq NAME EXPECTED ACTUAL
	if [[ $2 == "$3" ]]; then
		pass=$((pass + 1))
	else
		failed=$((failed + 1))
		printf 'FAIL %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
	fi
}
fails() { # fails NAME COMMAND...: the command must exit non-zero
	local name=$1
	shift
	if ("$@") >/dev/null 2>&1; then
		failed=$((failed + 1))
		printf 'FAIL %s: expected a failure\n' "$name"
	else
		pass=$((pass + 1))
	fi
}
skip() { # skip NAME REASON: a test that cannot run here, counted and reported
	skipped=$((skipped + 1))
	printf 'SKIP %s: %s\n' "$1" "$2"
}

# shellcheck disable=SC2034 # used by tests/t-*.sh
P=pci=hpbussize=0x80,hpmmiosize=32M,hpmmioprefsize=32G
# shellcheck disable=SC2034
OSI='acpi_osi=\"!Windows 2022\"'

for t in tests/t-*.sh; do
	# shellcheck source=/dev/null
	. "$t"
done

echo "tests: $pass passed, $failed failed, $skipped skipped"
[[ $failed -eq 0 ]]
