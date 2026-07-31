#!/bin/bash
# Build Pickroom.app, ad-hoc sign every code bundle, and optionally create a DMG.
#
# Ad-hoc signing (`codesign --sign -`) needs no paid Apple Developer account.
# It verifies bundle integrity but is not Developer ID signing or notarization,
# so a DMG downloaded from GitHub will still be quarantined by Gatekeeper.
#
# Env:
#   VERSION, BUILD   values written to the generated Info.plist
#   DEST             output directory                         (default ./dist)
#   UNIVERSAL=0      build only for the current Mac
#   DMG=0            stop after assembling Pickroom.app
#   SMOKE=1          launch the built executable briefly
set -euo pipefail

APP_NAME="Pickroom"
BUNDLE_ID="com.junyizhang.Pickroom"
PROJECT="Pickroom.xcodeproj"
SCHEME="Pickroom"
UNIVERSAL="${UNIVERSAL:-1}"
DMG="${DMG:-1}"
SMOKE="${SMOKE:-0}"
BUILD="${BUILD:-1}"

cd "$(dirname "$0")/.."

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

# Build unsigned so the release path is independent of local Apple accounts.
# The finished bundle is signed explicitly below, including nested frameworks.
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT_APP" ] || {
    echo "error: xcodebuild finished but no app exists at $BUILT_APP" >&2
    exit 1
}

echo "==> Assembling $APP_NAME.app"
/usr/bin/ditto "$BUILT_APP" "$APP"
/usr/bin/xattr -cr "$APP"

sign_path() {
    /usr/bin/codesign \
        --force \
        --sign - \
        --timestamp=none \
        --generate-entitlement-der \
        "$1"
}

echo "==> Ad-hoc signing nested code"
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

echo "==> Ad-hoc signing app"
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

if [ "$DMG" != "1" ]; then
    echo
    echo "Built:"
    echo "  $APP"
    echo "  version: $ACTUAL_VERSION ($ACTUAL_BUILD)"
    echo "  archs: $ACTUAL_ARCHS"
    exit 0
fi

echo "==> Building DMG"
STAGE="$DIST/dmg"
rm -rf "$STAGE" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
/usr/bin/hdiutil create \
    -quiet \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
rm -rf "$STAGE"

(
    cd "$DIST"
    /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")" >"$(basename "$CHECKSUM_PATH")"
)

echo
echo "Built:"
echo "  $APP"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
echo "  version: $ACTUAL_VERSION ($ACTUAL_BUILD)"
echo "  archs: $ACTUAL_ARCHS"
