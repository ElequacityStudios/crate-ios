#!/bin/bash
# Sign an unsigned crate IPA (the ipa workflow's) with this Mac's development
# certificate and team profiles, as Xcode signs a Debug build, and optionally
# install it on an iPhone.
#
#     ./Scripts/sign-ipa.sh crate-unsigned.ipa                  # writes crate-signed.ipa beside it
#     ./Scripts/sign-ipa.sh crate-unsigned.ipa --install UDID   # and installs it
#
# The app gets its own team profile, which has to grant both memory
# entitlements (Xcode makes it on a first -allowProvisioningUpdates build);
# the JIT helper gets its own or the team's wildcard one. Both get
# get-task-allow, which turning JIT on needs: the debugger attaches to crate.
# IDENTITY picks a certificate other than the first Apple Development one.
set -euo pipefail

TEAM=L29MY952CB
APP_ID=com.amendez.crate
HELPER_ID=com.amendez.crate.jithelper

IPA="$(cd "$(dirname "${1:?usage: $0 IPA [--install DEVICE]}")" && pwd)/$(basename "$1")"
DEVICE=""
[ "${2:-}" = --install ] && DEVICE="${3:?--install needs a device}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
[ -n "$IDENTITY" ] || { echo "no Apple Development certificate in the keychain" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The newest unexpired profile of this team whose app ID is TEAM.$1, or else,
# when $2 is "wildcard", the newest of the team's wildcard ones.
profile_for() {
    local id="$1" fallback="${2:-}" now path app date
    local exact="" exact_date="" wild="" wild_date=""
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for path in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision \
                "$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision; do
        [ -e "$path" ] || continue
        security cms -D -i "$path" > "$WORK/profile.plist" 2>/dev/null || continue
        app="$(plutil -extract Entitlements.application-identifier raw -o - "$WORK/profile.plist" 2>/dev/null)" || continue
        date="$(plutil -extract ExpirationDate raw -o - "$WORK/profile.plist")"
        [[ "$date" > "$now" ]] || continue
        if [ "$app" = "$TEAM.$id" ] && [[ "$date" > "$exact_date" ]]; then
            exact="$path" exact_date="$date"
        elif [ "$fallback" = wildcard ] && [ "$app" = "$TEAM.*" ] && [[ "$date" > "$wild_date" ]]; then
            wild="$path" wild_date="$date"
        fi
    done
    [ -n "$exact$wild" ] || { echo "no provisioning profile for $TEAM.$id: build the app once in Xcode" >&2; return 1; }
    echo "${exact:-$wild}"
}

# $WORK/ID.entitlements: the bundle's own (OWN, if any), its app ID and team,
# and get-task-allow as its profile grants it. Called as a statement, not in
# $(...), so a failure stops the script: macOS's bash 3.2 can't inherit -e.
entitlements_for() {
    local id="$1" profile="$2" own="${3:-}" out="$WORK/$1.entitlements" allow
    if [ -n "$own" ]; then cp "$own" "$out"; else plutil -create xml1 "$out"; fi
    security cms -D -i "$profile" > "$WORK/profile.plist"
    allow="$(plutil -extract Entitlements.get-task-allow raw -o - "$WORK/profile.plist")"
    # plutil splits key paths at dots unless they're escaped.
    plutil -replace application-identifier -string "$TEAM.$id" "$out"
    plutil -replace 'com\.apple\.developer\.team-identifier' -string "$TEAM" "$out"
    plutil -replace get-task-allow -bool "$allow" "$out"
}

sign() { codesign --force --sign "$IDENTITY" --timestamp=none "$@"; }

ditto -x -k "$IPA" "$WORK/ipa"
APP="$(echo "$WORK"/ipa/Payload/*.app)"
HELPER="$APP/PlugIns/CrateJITHelper.appex"
[ -d "$HELPER" ] || { echo "no CrateJITHelper.appex in $IPA" >&2; exit 1; }

app_profile="$(profile_for "$APP_ID")"
helper_profile="$(profile_for "$HELPER_ID" wildcard)"
echo "app:    $(security cms -D -i "$app_profile" | plutil -extract Name raw -o - -)"
echo "helper: $(security cms -D -i "$helper_profile" | plutil -extract Name raw -o - -)"

# Inside out: every embedded framework, then the helper, then the app.
for framework in "$HELPER"/Frameworks/*.framework "$APP"/Frameworks/*.framework; do
    [ -e "$framework" ] && sign "$framework"
done
entitlements_for "$HELPER_ID" "$helper_profile"
cp "$helper_profile" "$HELPER/embedded.mobileprovision"
sign --entitlements "$WORK/$HELPER_ID.entitlements" "$HELPER"
entitlements_for "$APP_ID" "$app_profile" "$REPO/Resources/Crate.entitlements"
cp "$app_profile" "$APP/embedded.mobileprovision"
sign --entitlements "$WORK/$APP_ID.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

OUT="${IPA%-unsigned.ipa}"
OUT="${OUT%.ipa}-signed.ipa"
rm -f "$OUT"
(cd "$WORK/ipa" && ditto -c -k --keepParent Payload "$OUT")
echo "signed: $OUT"

if [ -n "$DEVICE" ]; then
    xcrun devicectl device install app --device "$DEVICE" "$APP"
fi
