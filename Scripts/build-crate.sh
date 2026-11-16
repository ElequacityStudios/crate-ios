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

# Fail the IPA build unless the engine contains the complete, gated Venus
# protocol and the iOS relative-mouse capture fixes.
if ! grep -Fq 'CAPSET_VENUS: u32 = 4' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'F_CONTEXT_INIT: u64 = 1 << 4' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq 'virgl_renderer_context_create_with_flags' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'virgl_renderer_context_create_fence' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'write_context_fence: Some(write_context_fence)' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'VIRGL_RENDERER_VENUS: c_int = 1 << 6' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'VIRGL_RENDERER_RENDER_SERVER: c_int = 1 << 9' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'let venus_enabled = virgl_library.name.contains("virglrenderer.venus")' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'renderer_flags |= VIRGL_RENDERER_VENUS | VIRGL_RENDERER_RENDER_SERVER' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'capsets.retain(|capset| capset.id != CAPSET_VENUS)' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq 'context_fenced: VecDeque<FencedContext>' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq 'context_init_enabled = activation.features & F_CONTEXT_INIT != 0' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq '(!self.context_init_enabled || !request.fenced())' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq 'has_fences = !self.fenced.is_empty() || !self.context_fenced.is_empty()' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq 'memory_kind == 1 && count == 0' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq '(total as u64) < size' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq 'source_end > *size' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/mod.rs" \
    || ! grep -Fq 'self.blob_backings.remove(&resource)' "$CRATE_DIR/crates/crate-host/src/virgl.rs" \
    || ! grep -Fq 'venus_context_init_and_timeline_fences_are_forwarded' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/tests.rs" \
    || ! grep -Fq 'venus_capset_does_not_force_context_init_without_feature_negotiation' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/tests.rs" \
    || ! grep -Fq 'venus_host_blob_maps_and_scans_out' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/tests.rs" \
    || ! grep -Fq 'venus_default_blob_can_attach_and_detach_backing_later' "$CRATE_DIR/crates/crate-devices/src/virtio/gpu/tests.rs" \
    || ! grep -Fq 'override var prefersPointerLocked: Bool { isCaptured }' "$REPO/Sources/Crate/Home/MachineScreen.swift" \
    || ! grep -Fq 'dy: Int32((-dy).rounded())' "$REPO/Sources/Crate/Engine/DisplayView.swift" \
    || ! grep -Fq 'input.scroll.valueChangedHandler' "$REPO/Sources/Crate/Engine/DisplayView.swift" \
    || ! grep -Fq 'key.charactersIgnoringModifiers == UIKeyCommand.inputEscape' "$REPO/Sources/Crate/Engine/DisplayView.swift" \
    || ! grep -Fq 'let rect = mouseCaptured ? bounds : pointerArea' "$REPO/Sources/Crate/Engine/DisplayView.swift" \
    || ! grep -Fq 'releaseButton.isHidden = !captured' "$REPO/Sources/Crate/Home/MachineScreen.swift" \
    || ! grep -Fq 'crate_childForScreenEdgesDeferringSystemGestures' "$REPO/Sources/Crate/Engine/PointerLockSupport.swift" \
    || ! grep -Fq 'touch.type == .indirectPointer' "$REPO/Sources/Crate/Engine/PointerLockSupport.swift"; then
    echo "engine checkout lacks the complete Venus/blob protocol or the iOS mouse-capture fixes" >&2
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
