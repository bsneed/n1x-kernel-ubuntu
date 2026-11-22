# SPDX-License-Identifier: GPL-2.0-only
# Tests of scripts/config-check.sh.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash

# --- config-check.sh -------------------------------------------------------------------------
printf 'CONFIG_A=y\n# CONFIG_B is not set\nCONFIG_C="x y"\nCONFIG_D=m\n' >"$T/.config"
printf '# comment\nCONFIG_A=y\n# CONFIG_B is not set\nCONFIG_C="x y"\n# CONFIG_E is not set\n' >"$T/good.frag"
eq "config-check passes" 0 "$(bash scripts/config-check.sh "$T/good.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf 'CONFIG_D=y\n' >"$T/bad.frag"
eq "config-check catches a changed value" 1 "$(bash scripts/config-check.sh "$T/bad.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf 'CONFIG_Z=m\n' >"$T/gone.frag"
eq "config-check catches a dropped option" 1 "$(bash scripts/config-check.sh "$T/gone.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf '# CONFIG_A is not set\n' >"$T/off.frag"
eq "config-check catches an option left on" 1 "$(bash scripts/config-check.sh "$T/off.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
printf '# nothing\n' >"$T/empty.frag"
eq "config-check rejects an empty fragment" 1 "$(bash scripts/config-check.sh "$T/empty.frag" "$T/.config" >/dev/null 2>&1; echo $?)"
eq "config-check rejects a missing config" 2 "$(bash scripts/config-check.sh "$T/good.frag" "$T/none" >/dev/null 2>&1; echo $?)"
