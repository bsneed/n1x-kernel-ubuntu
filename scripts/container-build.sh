#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# n1x-kernel-ubuntu - run scripts/build.sh in a clean ubuntu:26.04 arm64 container
#
# Why: the packages must be built with Ubuntu 26.04's toolchain (gcc, rustc, pahole) so that the
# headers package works for DKMS on the target; a container gives that on any arm64 Docker host
# (a DGX Spark, a cloud arm64 runner) without installing build dependencies on the host.
# The checkout is mounted at /src and build/, out/ are written there, owned by the caller.
# Remove: rm -rf build out; docker image rm ubuntu:26.04
# Run with: bash scripts/container-build.sh [build.sh options]
set -euo pipefail
. "$(dirname "$0")/lib.sh"

command -v docker >/dev/null || die "docker not found"
IMAGE=${N1X_BUILD_IMAGE:-ubuntu:26.04}

docker run --rm --platform linux/arm64 \
	-v "$REPO:/src" -w /src \
	-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
	"$IMAGE" bash -c '
		set -euo pipefail
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq
		xargs -a scripts/build-deps.txt apt-get install -y -qq --no-install-recommends >/dev/null
		groupadd -o -g "$HOST_GID" builder 2>/dev/null || true
		useradd -o -m -u "$HOST_UID" -g "$HOST_GID" builder 2>/dev/null || true
		exec setpriv --reuid="$HOST_UID" --regid="$HOST_GID" --init-groups \
			env HOME=/home/builder bash scripts/build.sh "$@"
	' bash "$@"
