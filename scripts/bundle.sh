#!/bin/bash
# Build Pickroom.app, sign every code bundle inside it, and (by default) wrap
# the result in a DMG.
#
# Signing has two tiers and the script picks whichever this machine can do:
#
#   Developer ID  a "Developer ID Application" certificate in the keychain.
#                 Signed with the hardened runtime and a secure timestamp,
#                 then — if notarytool credentials are stored — submitted to
#                 Apple and stapled. That is the combination Gatekeeper wants
#                 from a DMG that travelled over the network.
#   ad-hoc        no such certificate. Runs on this machine and on any Mac
#                 you copy it to by hand, but a downloaded DMG picks up a
#                 quarantine flag and Gatekeeper refuses it.
#
# Env:
#   VERSION, BUILD   values written to the generated Info.plist
#   DEST             output directory                          (default ./dist)
#   UNIVERSAL=0      build only for the current Mac
#   DMG=0            stop after assembling Pickroom.app
#   SMOKE=1          launch the built executable briefly
#   SIGN_ID          codesign identity        (default: the Developer ID
#                    Application certificate found in the keychain)
#   SIGN_ID=-        force ad-hoc even when a certificate is present
#   NOTARIZE=0       Developer ID sign, but skip Apple's notary service
#   NOTARY_PROFILE   notarytool keychain profile      (default: the first of
#                    "pickroom thegit" the keychain answers for)
#   NOTARY_TIMEOUT   how long to wait for one verdict            (default 2h)
#   NOTARY_RETRIES   fresh submissions before giving up          (default 1)
set -euo pipefail

APP_NAME="Pickroom"
BUNDLE_ID="com.junyizhang.Pickroom"
PROJECT="Pickroom.xcodeproj"
SCHEME="Pickroom"
UNIVERSAL="${UNIVERSAL:-1}"
DMG="${DMG:-1}"
SMOKE="${SMOKE:-0}"
BUILD="${BUILD:-1}"
NOTARIZE="${NOTARIZE:-1}"

cd "$(dirname "$0")/.."

# notarise(), verify_distribution(), build_dmg() and the NOTARY_* defaults
# live in one place because notarise-release.sh needs exactly the same rules
# to backfill a ticket onto a release that shipped while Apple's queue was
# down, and release.sh needs the same checks to gate the tag.
. "$(dirname "$0")/release-lib.sh"

SIGN_ID="${SIGN_ID:-$(find_sign_id)}"
SIGN_ID="${SIGN_ID:--}"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
ROOT="$PWD"
DIST="${DEST:-$ROOT/dist}"
DERIVED_DATA="$ROOT/.build/release-derived-data"
APP="$DIST/$APP_NAME.app"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

if [ "$UNIVERSAL" = "1" ]; then
    ARCHS="arm64 x86_64"
    echo "==> Building universal Release app"
else
    ARCHS="$(uname -m)"
    echo "==> Building Release app for $ARCHS"
fi

rm -rf "$DERIVED_DATA" "$APP"
mkdir -p "$DIST"

# Built unsigned and signed explicitly below. Xcode's automatic signing picks
# whatever provisioning the machine happens to have, which is a different
# certificate on a different Mac; a release has to be reproducible from the
# script rather than from a local Xcode account. CODE_SIGNING_ALLOWED=NO also
# keeps get-task-allow out of the bundle, which notarisation rejects outright.
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    "ARCHS=$ARCHS" \
    "ONLY_ACTIVE_ARCH=NO" \
    "CODE_SIGNING_ALLOWED=NO" \
    "MARKETING_VERSION=$VERSION" \
    "CURRENT_PROJECT_VERSION=$BUILD" \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT_APP" ] || {
    echo "error: xcodebuild finished but no app exists at $BUILT_APP" >&2
    exit 1
}

echo "==> Assembling $APP_NAME.app"
/usr/bin/ditto "$BUILT_APP" "$APP"
/usr/bin/xattr -cr "$APP"

# --options runtime is what makes a signature notarisable, and it is also why
# this can't be bolted on at release time: the hardened runtime changes how
# the app behaves at launch, so the build that gets smoke tested below has to
# be the build that was signed this way.
sign_path() {
    if [ "$SIGN_ID" = "-" ]; then
        /usr/bin/codesign \
            --force \
            --sign - \
            --timestamp=none \
            --generate-entitlement-der \
            "$1"
    else
        /usr/bin/codesign \
            --force \
            --options runtime \
            --timestamp \
            --sign "$SIGN_ID" \
            "$1"
    fi
}

if [ "$SIGN_ID" = "-" ]; then
    echo "==> Ad-hoc signing (no Developer ID certificate in the keychain)"
else
    echo "==> Signing with $SIGN_ID"
fi

# Inside out: codesign seals a bundle's nested code into the enclosing
# signature, so anything signed after its container invalidates the container.
if [ -d "$APP/Contents/Frameworks" ]; then
    find "$APP/Contents/Frameworks" -type f -name '*.dylib' -print0 |
        while IFS= read -r -d '' item; do
            sign_path "$item"
        done

    find "$APP/Contents/Frameworks" -type d -name '*.framework' -prune -print0 |
        while IFS= read -r -d '' item; do
            sign_path "$item"
        done
fi

for directory in "$APP/Contents/PlugIns" "$APP/Contents/XPCServices"; do
    if [ -d "$directory" ]; then
        find "$directory" -type d \( -name '*.appex' -o -name '*.xpc' \) -prune -print0 |
            while IFS= read -r -d '' item; do
                sign_path "$item"
            done
    fi
done

sign_path "$APP"

echo "==> Verifying bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

INFO_PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
ACTUAL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[ "$ACTUAL_ID" = "$BUNDLE_ID" ] || {
    echo "error: expected bundle id $BUNDLE_ID, got $ACTUAL_ID" >&2
    exit 1
}
[ "$ACTUAL_VERSION" = "$VERSION" ] || {
    echo "error: expected version $VERSION, got $ACTUAL_VERSION" >&2
    exit 1
}
[ "$ACTUAL_BUILD" = "$BUILD" ] || {
    echo "error: expected build $BUILD, got $ACTUAL_BUILD" >&2
    exit 1
}

ACTUAL_ARCHS="$(/usr/bin/lipo -archs "$EXECUTABLE")"
if [ "$UNIVERSAL" = "1" ]; then
    echo "$ACTUAL_ARCHS" | grep -qw arm64 || {
        echo "error: universal app is missing arm64" >&2
        exit 1
    }
    echo "$ACTUAL_ARCHS" | grep -qw x86_64 || {
        echo "error: universal app is missing x86_64" >&2
        exit 1
    }
fi

# Before notarisation, not after: a hardened-runtime app that dies on launch
# should fail here in three seconds rather than after a wait on Apple's queue
# that can run to hours.
if [ "$SMOKE" = "1" ]; then
    echo "==> Smoke launching app"
    LOG="$DIST/$APP_NAME-smoke.log"
    "$EXECUTABLE" >"$LOG" 2>&1 &
    PID=$!
    sleep 3
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "error: $APP_NAME exited during smoke launch" >&2
        cat "$LOG" >&2
        exit 1
    fi
    kill "$PID"
    wait "$PID" 2>/dev/null || true
    rm -f "$LOG"
fi

# Notarise the .app before it goes in the DMG, not just the DMG afterwards.
# A ticket stapled to the DMG only covers the DMG: drag the app to
# /Applications, throw the DMG away, and the first launch on a Mac that is
# offline has nothing local to check. Stapling both costs one extra round
# trip and makes the app self-contained.
CAN_NOTARISE=0
if [ "$SIGN_ID" != "-" ] && [ "$NOTARIZE" = "1" ]; then
    # Assigned back explicitly: notary_profile() caches into NOTARY_PROFILE,
    # but a command substitution runs in a subshell, so the cache would be
    # thrown away and every later call would re-probe Apple.
    if PROFILE="$(notary_profile)"; then
        NOTARY_PROFILE="$PROFILE"
        echo "==> Using notarytool profile '$NOTARY_PROFILE'"
        CAN_NOTARISE=1
    else
        echo "    (no notarytool profile in $NOTARY_PROFILE_CANDIDATES — skipping notarisation)"
    fi
fi

if [ "$CAN_NOTARISE" = "1" ]; then
    # notarytool takes a zip, a DMG or a pkg — never a bare .app — so the
    # bundle goes up zipped and the ticket comes back onto the .app itself.
    ZIP="$DIST/$APP_NAME-notarise.zip"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
    if ! notarise "$ZIP" "$APP"; then rm -f "$ZIP"; exit 1; fi
    rm -f "$ZIP"
    # Asked here rather than assumed from a clean exit: everything above
    # reports success on a build whose ticket never landed, and the failure
    # only shows up on someone else's Mac.
    verify_distribution "$APP" execute || exit 1
fi

if [ "$DMG" != "1" ]; then
    echo
    echo "Built:"
    echo "  $APP"
    echo "  version: $ACTUAL_VERSION ($ACTUAL_BUILD)"
    echo "  archs: $ACTUAL_ARCHS"
    exit 0
fi

echo "==> Building DMG"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"
build_dmg "$APP" "$DMG_PATH" "$APP_NAME" "$SIGN_ID"

if [ "$CAN_NOTARISE" = "1" ]; then
    notarise "$DMG_PATH" "$DMG_PATH"
    verify_distribution "$DMG_PATH" open || exit 1
fi

# Last, so the hash belongs to the finished image rather than to the one that
# existed before a ticket was stapled into it.
write_checksum "$DMG_PATH"

echo
echo "Built:"
echo "  $APP"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
echo "  version: $ACTUAL_VERSION ($ACTUAL_BUILD)"
echo "  archs: $ACTUAL_ARCHS"
