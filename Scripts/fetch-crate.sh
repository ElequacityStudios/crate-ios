#!/bin/bash
# Fetch crate, the VM engine, as Frameworks/Crate.xcframework: the release of
# github.com/oneamendez/crate pinned below, checked against its SHA-256, so
# moving to another engine is a commit here. Imported in Swift as `CrateEngine`.
# Scripts/build-crate.sh builds it from a checkout instead, for changing crate.
#
#     ./Scripts/fetch-crate.sh
#
# CRATE_ZIP=path uses a zip made by crate's tools/xcframework.sh instead of
# downloading, with CRATE_SHA256 its hash, to try a build before it's released.
set -euo pipefail

VERSION=v0.1.0
SHA256=c9008755614e25d62e488bbfaec2614047db3247056d95949cc2820f3119342c
SHA256="${CRATE_SHA256:-$SHA256}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO/Frameworks"
if [ -z "${CRATE_ZIP:-}" ] && [ "$(cat "$DEST/Crate.version" 2>/dev/null)" = "$VERSION" ] \
        && [ -d "$DEST/Crate.xcframework" ]; then
    echo "crate $VERSION already in Frameworks/"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [ -n "${CRATE_ZIP:-}" ]; then
    cp "$CRATE_ZIP" "$WORK/Crate.xcframework.zip"
    VERSION="$(basename "$CRATE_ZIP")"
else
    curl --fail --location --silent --show-error --output "$WORK/Crate.xcframework.zip" \
        "https://github.com/oneamendez/crate/releases/download/$VERSION/Crate.xcframework.zip"
fi
echo "$SHA256  $WORK/Crate.xcframework.zip" | shasum -a 256 --check --quiet
mkdir "$WORK/out"
ditto -x -k "$WORK/Crate.xcframework.zip" "$WORK/out"
[ -d "$WORK/out/Crate.xcframework" ] || { echo "no Crate.xcframework in the zip" >&2; exit 1; }
mkdir -p "$DEST"
rm -rf "$DEST/Crate.xcframework"
mv "$WORK/out/Crate.xcframework" "$DEST/"
echo "$VERSION" > "$DEST/Crate.version"
echo "crate $VERSION in Frameworks/"
