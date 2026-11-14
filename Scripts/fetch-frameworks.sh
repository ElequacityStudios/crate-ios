#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Fetch the frameworks the app builds with (idevice, libslirp and GLib, and the
# GPU stack) from the release of this repository pinned below, checked against
# its SHA-256, instead of building them. Scripts/release-frameworks.sh made it
# from the build scripts' output; building them yourself gives the same files.
#
#     ./Scripts/fetch-frameworks.sh
#
# This repository is private, so the download needs a token that can read it:
# GH_TOKEN, or else gh's login as oneamendez on this Mac.
set -euo pipefail

VERSION=frameworks-2026.11.13
SHA256=585817460ab5f47b9782339e62d7e27731536096518863ef305a6696d1595be9

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO/Frameworks"
if [ "$(cat "$DEST/Frameworks.version" 2>/dev/null)" = "$VERSION" ] && [ -d "$DEST/GPU" ]; then
    echo "frameworks $VERSION already in Frameworks/"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GH_TOKEN="${GH_TOKEN:-$(gh auth token -u oneamendez)}"
gh release download "$VERSION" -R oneamendez/crate-ios -p Frameworks.zip -D "$WORK"
echo "$SHA256  $WORK/Frameworks.zip" | shasum -a 256 --check --quiet
ditto -x -k "$WORK/Frameworks.zip" "$WORK/out"
mkdir -p "$DEST"
for item in "$WORK"/out/Frameworks/*; do
    rm -rf "$DEST/$(basename "$item")"
    mv "$item" "$DEST/"
done
echo "$VERSION" > "$DEST/Frameworks.version"
echo "frameworks $VERSION in Frameworks/"
