#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Build a separate Venus-enabled virglrenderer for iOS. The existing
# virglrenderer.1.framework remains the OpenGL fallback; crate will load this
# framework only for its Vulkan/Venus backend.
#
# The renderer is UTM's macOS/Metal Venus port, kept at the protocol snapshot
# used by the app's Mesa 26.2.x guest. Do not merge the newer Mesa 26.3
# protocol update: Venus's generated wire schema must match the guest exactly,
# or guest vkCreateInstance can fail with the misleading OUT_OF_HOST_MEMORY.
# The pinned steamac fixes are Apache-2.0 and remain attributed to fxgl/steamac.
# Vulkan is loaded at runtime, never linked.
set -euo pipefail

EPOXY_VERSION=1.5.10
EPOXY_SHA256=a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15
ANGLE_REV=9addc2983b90152f628cfdaea194983b46b254bd
UTM_COMMIT=5d26f605f50f8e22002ec6db5fb775e1992d4e96
STEAMAC_COMMIT=32a66354a24cc62d4c9ec1d263c5df7a0b1e1d7e
MIN_IOS=18.0

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$REPO/.deps"
SRC="$DEPS/src"
WORK="$DEPS/virgl-venus-build"
DEST="$REPO/Frameworks/GPU"
HEADERS="$DEPS/angle-include"
STAMP="UTM virglrenderer $UTM_COMMIT; Mesa 26.2 Venus protocol; steamac $STEAMAC_COMMIT; Venus capset 4; MoltenVK framework loader; libepoxy $EPOXY_VERSION; iOS $MIN_IOS"

if [ "$(cat "$DEST/virglrenderer.venus.version" 2>/dev/null)" = "$STAMP" ] \
    && [ -d "$DEST/virglrenderer.venus.framework" ] && [ -d "$DEST/epoxy.framework" ]; then
    echo "$STAMP already in Frameworks/GPU/"
    exit 0
fi

for dep in meson ninja pkg-config; do
    command -v "$dep" >/dev/null 2>&1 || {
        echo "missing $dep; install with brew install meson ninja pkgconf" >&2
        exit 1
    }
done

mkdir -p "$SRC" "$DEPS"
fetch() {
    [ -f "$SRC/$2" ] || curl --fail --location --silent --show-error --output "$SRC/$2" "$1"
    echo "$3  $SRC/$2" | shasum -a 256 --check --quiet
}
fetch "https://github.com/anholt/libepoxy/archive/refs/tags/$EPOXY_VERSION.tar.gz" \
      "libepoxy-$EPOXY_VERSION.tar.gz" "$EPOXY_SHA256"

rm -rf "$WORK"
mkdir -p "$WORK"

# Only ANGLE's public headers are needed here; do not run gclient sync or build
# another copy of ANGLE. The app already embeds its pinned iOS frameworks.
ANGLE_SRC="$WORK/angle-headers"
git init -q "$ANGLE_SRC"
git -C "$ANGLE_SRC" remote add origin https://chromium.googlesource.com/angle/angle.git
git -C "$ANGLE_SRC" fetch -q --depth=1 origin "$ANGLE_REV"
git -C "$ANGLE_SRC" checkout -q --detach FETCH_HEAD
mkdir -p "$HEADERS"
cp -R "$ANGLE_SRC/include/." "$HEADERS/"
[ -f "$HEADERS/EGL/egl.h" ] || { echo "ANGLE EGL headers missing" >&2; exit 1; }

# Fetch the exact upstream patch set and merge resolver used by steamac.
STEAMAC_DIR="$WORK/steamac"
git init -q "$STEAMAC_DIR"
git -C "$STEAMAC_DIR" remote add origin https://github.com/fxgl/steamac.git
git -C "$STEAMAC_DIR" fetch -q --depth=1 origin "$STEAMAC_COMMIT"
git -C "$STEAMAC_DIR" checkout -q --detach FETCH_HEAD

# UTM's fork carries the macOS/Metal Venus port and the generated protocol
# schema matching the app's Mesa 26.2.x guest. Keep this snapshot intact:
# the upstream Mesa 26.3 protocol update changes the generated wire schema.
git init -q "$WORK/virglrenderer"
git -C "$WORK/virglrenderer" remote add origin https://github.com/utmapp/virglrenderer.git
git -C "$WORK/virglrenderer" fetch -q --depth=1 origin "$UTM_COMMIT"
git -C "$WORK/virglrenderer" checkout -q -f --detach FETCH_HEAD
git -C "$WORK/virglrenderer" clean -q -fdx

# Fail closed if the pinned source's generated protocol drifts away from the
# Mesa 26.2.x guest ABI. This header advertises both the Vulkan XML revision
# and VK_MESA_venus_protocol spec version to the guest during initialization.
PROTOCOL_INFO="$WORK/virglrenderer/src/venus/venus-protocol/vn_protocol_renderer_info.h"
grep -Fq 'return VK_MAKE_API_VERSION(0, 1, 4, 343);' "$PROTOCOL_INFO" || {
    echo "UTM Venus protocol no longer matches the Mesa 26.2.x Vulkan XML revision" >&2
    exit 1
}
grep -Fq '{ "VK_MESA_venus_protocol", 385, 4 }' "$PROTOCOL_INFO" || {
    echo "UTM Venus protocol no longer matches the Mesa 26.2.x extension revision" >&2
    exit 1
}
if git -C "$WORK/virglrenderer" grep -qE '^(<<<<<<<|>>>>>>>) ' -- '*.c' '*.h' '*.build'; then
    echo "unresolved virglrenderer conflict markers" >&2
    exit 1
fi
for patch in "$STEAMAC_DIR"/host/virglrenderer/patches/*.patch; do
    [ -e "$patch" ] || continue
    echo "==> applying $(basename "$patch")"
    git -C "$WORK/virglrenderer" apply --whitespace=nowarn "$patch"
done

# The pinned steamac loader defaults to libMoltenVK.dylib. This app embeds
# MoltenVK as a framework, so change the default while preserving the env override.
python3 - "$WORK/virglrenderer/src/venus/vkr_library.c" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'return path && *path ? path : "@rpath/libMoltenVK.dylib";'
new = 'return path && *path ? path : "@rpath/MoltenVK.framework/MoltenVK";'
if source.count(old) != 1:
    raise SystemExit("could not find the unique VKR_VULKAN_DRIVER default in vkr_library.c")
path.write_text(source.replace(old, new))
PY

# The Venus protocol generator needs Mako; Gallium's generators need PyYAML.
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" -q install "pyyaml==6.0.3" "mako==1.3.10"
export PATH="$WORK/venv/bin:$PATH"

sysroot="$(xcrun --sdk iphoneos --show-sdk-path)"
target="arm64-apple-ios$MIN_IOS"
flags="'-target', '$target', '-isysroot', '$sysroot', '-I$HEADERS'"
links="'-target', '$target', '-isysroot', '$sysroot', '-Wl,-rpath,@loader_path/..'"
cat > "$WORK/cross.ini" <<CROSS
[binaries]
c = ['$(xcrun --sdk iphoneos -f clang)']
objc = ['$(xcrun --sdk iphoneos -f clang)']
cpp = ['$(xcrun --sdk iphoneos -f clang++)']
ar = '$(xcrun --sdk iphoneos -f ar)'
strip = '$(xcrun --sdk iphoneos -f strip)'
pkg-config = 'pkg-config'

[built-in options]
c_args = [$flags]
objc_args = [$flags]
cpp_args = [$flags]
c_link_args = [$links]
objc_link_args = [$links]
cpp_link_args = [$links]

[host_machine]
system = 'darwin'
subsystem = 'ios'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
CROSS

PREFIX="$WORK/prefix"
mkdir -p "$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=""

quietly() {
    "$@" > "$WORK/step.log" 2>&1 || { cat "$WORK/step.log" >&2; return 1; }
}

echo "==> libepoxy $EPOXY_VERSION"
tar -xf "$SRC/libepoxy-$EPOXY_VERSION.tar.gz" -C "$WORK"
patch --quiet -p1 -d "$WORK/libepoxy-$EPOXY_VERSION" < "$REPO/Scripts/patches/libepoxy-ios-angle.patch"
quietly meson setup "$WORK/epoxy" "$WORK/libepoxy-$EPOXY_VERSION" --cross-file "$WORK/cross.ini" \
    --prefix "$PREFIX" --buildtype release --default-library shared \
    -Degl=yes -Dglx=no -Dx11=false -Dtests=false -Ddocs=false
quietly meson compile -C "$WORK/epoxy"
quietly meson install -C "$WORK/epoxy"

echo "==> Venus-enabled virglrenderer"
quietly meson setup "$WORK/virgl" "$WORK/virglrenderer" --cross-file "$WORK/cross.ini" \
    --prefix "$PREFIX" --libdir lib --buildtype release --default-library shared \
    -Dplatforms=egl -Dvenus=true -Dvulkan-dload=true -Dvulkan-preload=false \
    -Drender-server-mode=thread -Drender-server-worker=thread \
    -Dneptune=false -Dvtest=false -Dtests=false -Dfuzzer=false -Dvideo=false \
    -Dminigbm_allocation=false -Dtracing=none -Dcheck-gl-errors=false
quietly meson compile -C "$WORK/virgl"
quietly meson install -C "$WORK/virgl"

framework() {
    local dylib="$1" name="$2"
    rm -rf "$DEST/$name.framework"
    mkdir -p "$DEST/$name.framework"
    cp "$dylib" "$DEST/$name.framework/$name"
    install_name_tool -id "@rpath/$name.framework/$name" "$DEST/$name.framework/$name"
    cat > "$DEST/$name.framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.amendez.crate.$name</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict></plist>
PLIST
}

mkdir -p "$DEST"
framework "$(ls "$PREFIX"/lib/libepoxy.*.dylib | head -1)" epoxy
VENUS_LIB="$(ls "$PREFIX"/lib/libvirglrenderer.*.dylib | head -1)"
framework "$VENUS_LIB" virglrenderer.venus

venus="$DEST/virglrenderer.venus.framework/virglrenderer.venus"
old="$(otool -L "$venus" | awk '/libepoxy/ {print $1}')"
[ -z "$old" ] || install_name_tool -change "$old" "@rpath/epoxy.framework/epoxy" "$venus"
if otool -L "$venus" | grep -qiE 'libvulkan|libMoltenVK'; then
    echo "Venus renderer links Vulkan instead of loading MoltenVK at runtime" >&2
    otool -L "$venus" >&2
    exit 1
fi
codesign --force -s - "$DEST/epoxy.framework" "$DEST/virglrenderer.venus.framework"
echo "$STAMP" > "$DEST/virglrenderer.venus.version"
echo "$STAMP in Frameworks/GPU/"
