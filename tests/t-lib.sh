# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib.sh: version parsing, ./sources and checksums.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash

# --- versions --------------------------------------------------------------------------------
eq "base of X.Y" 7.3.0 "$(kernel_base_version 7.3)"
eq "base of X.Y.Z" 7.3.5 "$(kernel_base_version 7.3.5)"
eq "base of 10.12" 10.12.0 "$(kernel_base_version 10.12)"
fails "base rejects X" kernel_base_version 7
fails "base rejects rc" kernel_base_version 7.3-rc1
fails "base rejects X.Y.Z.W" kernel_base_version 7.3.1.2
fails "base rejects empty" kernel_base_version ""
eq "release" 7.3.0-n1x1 "$(kernel_release 7.3 1)"
eq "release two digits" 7.3.5-n1x12 "$(kernel_release 7.3.5 12)"
fails "release rejects revision 0" kernel_release 7.3 0
fails "release rejects revision 01" kernel_release 7.3 01
fails "release rejects revision x" kernel_release 7.3 x
eq "is ours" 0 "$(is_n1x_release 7.3.0-n1x1; echo $?)"
eq "1026 is not ours" 1 "$(is_n1x_release 7.0.0-1026-nvidia; echo $?)"
eq "suffix is not ours" 1 "$(is_n1x_release 7.3.0-n1x1-foo; echo $?)"
eq "generic is not ours" 1 "$(is_n1x_release 7.0.0-44-generic; echo $?)"


# --- sources ---------------------------------------------------------------------------------
load_sources
eq "pinned release" "7.3.0-n1x$N1X_REVISION" "$(kernel_release "$KERNEL_VERSION" "$N1X_REVISION")"
grep -v '^NVIDIA_URL=' sources >"$T/sources"
# shellcheck disable=SC2016 # expanded by the inner bash
fails "load_sources needs every key" bash -c '. scripts/lib.sh; load_sources "$1"' _ "$T/sources"
fails "load_sources needs the file" load_sources "$T/missing"
printf 'x' >"$T/f"
fails "verify_sha256 mismatch" verify_sha256 "$T/f" 0000
eq "verify_sha256 match" ok "$(verify_sha256 "$T/f" 2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881 && echo ok)"
