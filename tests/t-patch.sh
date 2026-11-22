# SPDX-License-Identifier: GPL-2.0-only
# Tests of lib.sh's apply_patch, which scripts/build.sh and scripts/nvidia-dkms.sh use.
# Sourced by tests/run.sh, which defines eq, fails, $T, $P and $OSI.
# shellcheck shell=bash

mkdir -p "$T/ptree/src"
printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"
cat >"$T/fix.patch" <<'PATCH'
--- a/src/f.c
+++ b/src/f.c
@@ -1,3 +1,3 @@
 one
-two
+TWO
 three
PATCH
eq "patch applies" "0 one TWO three" "$(apply_patch "$T/ptree" "$T/fix.patch" >/dev/null 2>&1; echo $?) $(paste -sd' ' "$T/ptree/src/f.c")"
# An already-applied patch (merged upstream) must fail the build, not be reverted (GNU patch
# --batch alone assumes -R and exits 0).
fails "patch already applied fails" apply_patch "$T/ptree" "$T/fix.patch"
eq "patch already applied is not reverted" "one TWO three" "$(paste -sd' ' "$T/ptree/src/f.c")"
printf 'one\nzwei\nthree\n' >"$T/ptree/src/f.c"
fails "patch that does not fit fails" apply_patch "$T/ptree" "$T/fix.patch"
eq "patch that does not fit leaves the file" "one zwei three" "$(paste -sd' ' "$T/ptree/src/f.c")"
printf 'zero\none\ntwo\nthree\n' >"$T/ptree/src/f.c"
cat >"$T/fuzz.patch" <<'PATCH'
--- a/src/f.c
+++ b/src/f.c
@@ -1,3 +1,3 @@
 one
-two
+TWO
 four
PATCH
fails "patch needing fuzz fails" apply_patch "$T/ptree" "$T/fuzz.patch"
fails "patch in a missing tree fails" apply_patch "$T/nope" "$T/fix.patch"

# --- apply_patch_dir: build.sh applies patches/ubuntu with it -------------------------------
printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"
mkdir -p "$T/pdir" "$T/pempty"
cp "$T/fix.patch" "$T/pdir/0001-fix.patch"
cat >"$T/pdir/0002-on-top.patch" <<'PATCH'
--- a/src/f.c
+++ b/src/f.c
@@ -1,3 +1,3 @@
 one
-TWO
+2
 three
PATCH
printf 'not a patch\n' >"$T/pdir/README.md"
eq "patch dir: applied in name order, others ignored" "applied 0001-fix.patch applied 0002-on-top.patch|one 2 three" \
	"$(apply_patch_dir "$T/ptree" "$T/pdir" | paste -sd' ' -)|$(paste -sd' ' "$T/ptree/src/f.c")"
eq "patch dir without patches" "0 " "$(apply_patch_dir "$T/ptree" "$T/pempty"; echo "$? $(apply_patch_dir "$T/ptree" "$T/pempty")")"
fails "patch dir missing" apply_patch_dir "$T/ptree" "$T/nope"
printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"
cp "$T/fix.patch" "$T/pdir/0003-again.patch"
fails "patch dir with a patch that does not apply" apply_patch_dir "$T/ptree" "$T/pdir"
eq "patch dir: the failing patch is named" "0003-again.patch does not apply (already applied upstream, or no longer fits)" \
	"$(printf 'one\ntwo\nthree\n' >"$T/ptree/src/f.c"; apply_patch_dir "$T/ptree" "$T/pdir" 2>&1 >/dev/null)"

