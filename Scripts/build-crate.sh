#!/bin/bash
# Build crate, the VM engine (a repository of its own, ~/Repos/crate), as
# Frameworks/Crate.xcframework: its C API (include/crate.h) as a static library
# for iPhones and Apple-silicon Simulators, imported in Swift as `CrateEngine`
# (the app's own module is `Crate`).
#
#     ./Scripts/build-crate.sh                   # crate from ~/Repos/crate
#     CRATE_DIR=/path/to/crate ./Scripts/build-crate.sh
#
# Needs Rust with the aarch64-apple-ios and aarch64-apple-ios-sim targets. crate
# leaves libslirp to the app; until crate-ios has networking, NoNetwork.c stands
# in for it.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CRATE_DIR="${CRATE_DIR:-$HOME/Repos/crate}"
OUT="$REPO/Frameworks/Crate.xcframework"
TARGETS="aarch64-apple-ios aarch64-apple-ios-sim"
export PATH="$HOME/.cargo/bin:$PATH"
export IPHONEOS_DEPLOYMENT_TARGET=18.0

[ -f "$CRATE_DIR/include/crate.h" ] || { echo "no crate checkout at $CRATE_DIR (set CRATE_DIR)" >&2; exit 1; }
VERSION="$(git -C "$CRATE_DIR" rev-parse --short HEAD)$(git -C "$CRATE_DIR" diff --quiet || echo +changes)"
for target in $TARGETS; do
    rustup target list --installed | grep -qx "$target" || rustup target add "$target"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# In a folder named for the module, so its module map can't collide with another
# library's when Xcode copies headers into the build's include/.
mkdir -p "$WORK/include/CrateEngine"
cp "$CRATE_DIR/include/crate.h" "$WORK/include/CrateEngine/"
cat > "$WORK/include/CrateEngine/module.modulemap" <<'MAP'
module CrateEngine {
    header "crate.h"
    export *
}
MAP
ARGS=()
for target in $TARGETS; do
    cargo build --quiet --manifest-path "$CRATE_DIR/Cargo.toml" -p crate-ffi --release --target "$target"
    mkdir "$WORK/$target"
    cp "$CRATE_DIR/target/$target/release/libcrate_ffi.a" "$WORK/$target/libcrate.a"
    ARGS+=(-library "$WORK/$target/libcrate.a" -headers "$WORK/include")
done
rm -rf "$OUT"
mkdir -p "$REPO/Frameworks"
xcodebuild -create-xcframework "${ARGS[@]}" -output "$OUT" >/dev/null
echo "$VERSION" > "$REPO/Frameworks/Crate.version"
echo "crate $VERSION in Frameworks/"
