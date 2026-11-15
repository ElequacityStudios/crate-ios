#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Build crate, the VM engine, from a checkout (~/Repos/crate) as
# Frameworks/Crate.xcframework, with crate's own tools/xcframework.sh: the same
# library its releases hold, imported in Swift as `CrateEngine`. For changing
# crate and the app at once; Scripts/fetch-crate.sh gets the pinned release.
#
#     ./Scripts/build-crate.sh                   # crate from ~/Repos/crate
#     CRATE_DIR=/path/to/crate ./Scripts/build-crate.sh
#
# Needs Rust with the aarch64-apple-ios, aarch64-apple-ios-sim and
# aarch64-apple-darwin targets. crate leaves libslirp to the app:
# Scripts/build-slirp.sh builds it.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CRATE_DIR="${CRATE_DIR:-$HOME/Repos/crate}"
export PATH="$HOME/.cargo/bin:$PATH"

[ -f "$CRATE_DIR/include/crate.h" ] || { echo "no crate checkout at $CRATE_DIR (set CRATE_DIR)" >&2; exit 1; }
grep -q "module CrateEngine" "$CRATE_DIR/tools/xcframework.sh" || {
    echo "crate at $CRATE_DIR builds an older XCFramework: it needs the CrateEngine module (crate 0.1.0)" >&2
    exit 1
}

# Do not ship an IPA with blob support but without the complete Venus protocol:
# the engine must advertise capset 4 and VIRTIO_GPU_F_CONTEXT_INIT, and route
# context creation through virglrenderer_context_create_with_flags.
if ! grep -q 'CAPSET_VENUS: u32 = 4' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -q 'F_CONTEXT_INIT: u64 = 1 << 4' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -q 'virgl_renderer_context_create_with_flags' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -q 'virgl_renderer_context_create_fence' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -q 'write_context_fence: Some(write_context_fence)' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -q 'VIRGL_RENDERER_VENUS: c_int = 1 << 6' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -q 'VIRGL_RENDERER_USE_GLES | VIRGL_RENDERER_VENUS' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -q 'context_fenced: VecDeque<FencedContext>' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -q 'venus_context_init_and_timeline_fences_are_forwarded' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/tests.rs"; then
    echo "crate checkout lacks complete virtio-gpu Venus context initialization and timeline fences" >&2
    exit 1
fi
VERSION="$(git -C "$CRATE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
VERSION="$VERSION$(git -C "$CRATE_DIR" diff --quiet 2>/dev/null || echo +changes)"
for target in aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin; do
    rustup target list --installed | grep -qx "$target" || rustup target add "$target"
done

mkdir -p "$REPO/Frameworks"
"$CRATE_DIR/tools/xcframework.sh" "$REPO/Frameworks/Crate.xcframework" >/dev/null
echo "$VERSION" > "$REPO/Frameworks/Crate.version"
echo "crate $VERSION in Frameworks/"
