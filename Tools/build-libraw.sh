#!/bin/bash
# Build LibRaw as the universal macOS framework Pickroom links against.
#
# The repository ships the compiled xcframework, which is convenient and
# opaque: nobody, including whoever committed it, can tell from the binary
# whether it is stock upstream or carries a patch. CDDL cares about that —
# modified files have to be published — so this script exists to make the
# artefact reproducible and the answer checkable.
#
# LibRaw is dual licensed LGPL-2.1 / CDDL-1.0 and Pickroom uses it under
# CDDL-1.0. Nothing here patches it; the source is fetched from libraw.org,
# checksummed, and built as it comes.
#
# The configure flags are not arbitrary. They reproduce the dependency set of
# the framework already in the tree — zlib and nothing else — so a rebuild is
# a drop-in replacement rather than a behaviour change:
#
#   no jpeg    lossy-compressed DNG will not decode. That is the existing
#              behaviour, and adding libjpeg here would mean vendoring and
#              signing a second dylib.
#   no lcms    Pickroom converts colour itself.
#   no openmp  libomp is not a system library on macOS, so a build with it
#              would not run on a Mac that lacks Homebrew.
#
# Usage:
#   Tools/build-libraw.sh            build and replace the xcframework in place
#   DEST=/tmp/out Tools/build-libraw.sh   build somewhere else and compare
set -euo pipefail

VERSION="${VERSION:-0.22.2}"
# From libraw.org. A changed checksum means the upstream archive changed under
# a version number that is supposed to be immutable — stop rather than build it.
SHA256="${SHA256:-de86b035655accff8d4010f1a221fdf50d353cb7b1422ba26f14a0db92612cfa}"
URL="${URL:-https://www.libraw.org/data/LibRaw-$VERSION.tar.gz}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-14.0}"
ARCHS=("arm64" "x86_64")

cd "$(dirname "$0")/.."
ROOT="$PWD"
DEST="${DEST:-$ROOT/Packages/RawEngine/Libraries}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TARBALL="$WORK/LibRaw-$VERSION.tar.gz"
echo "==> Fetching LibRaw $VERSION"
curl -fsSL --max-time 300 -o "$TARBALL" "$URL"

ACTUAL="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "error: checksum mismatch for LibRaw-$VERSION.tar.gz" >&2
    echo "  expected $SHA256" >&2
    echo "  actual   $ACTUAL" >&2
    exit 1
fi
echo "    sha256 ok"

tar xzf "$TARBALL" -C "$WORK"
SRC="$WORK/LibRaw-$VERSION"

for ARCH in "${ARCHS[@]}"; do
    echo "==> Building $ARCH"
    BUILD="$WORK/build-$ARCH"
    cp -R "$SRC" "$BUILD"
    (
        cd "$BUILD"
        # --host stops autoconf from probing the build machine when the two
        # architectures differ; without it the x86_64 pass on an arm64 Mac
        # configures itself for the host and the compile fails late.
        HOST="$ARCH-apple-darwin"
        [ "$ARCH" = "arm64" ] && HOST="aarch64-apple-darwin"
        ./configure \
            --host="$HOST" \
            --prefix="$WORK/install-$ARCH" \
            --enable-shared \
            --disable-static \
            --enable-zlib \
            --disable-jpeg \
            --disable-lcms \
            --disable-openmp \
            --disable-examples \
            --disable-dependency-tracking \
            CFLAGS="-arch $ARCH -mmacosx-version-min=$DEPLOYMENT_TARGET -O2" \
            CXXFLAGS="-arch $ARCH -mmacosx-version-min=$DEPLOYMENT_TARGET -O2" \
            LDFLAGS="-arch $ARCH -mmacosx-version-min=$DEPLOYMENT_TARGET" \
            >/dev/null
        make -j"$(sysctl -n hw.ncpu)" >/dev/null
        make install >/dev/null
    )
done

echo "==> Assembling LibRaw.framework"
FRAMEWORK="$WORK/LibRaw.framework"
mkdir -p "$FRAMEWORK/Versions/A/"{Headers,Modules,Resources}
ln -s A "$FRAMEWORK/Versions/Current"
for item in Headers Modules Resources LibRaw; do
    ln -s "Versions/Current/$item" "$FRAMEWORK/$item"
done

DYLIBS=()
for ARCH in "${ARCHS[@]}"; do
    DYLIBS+=("$(ls "$WORK/install-$ARCH/lib/"libraw.*.dylib | head -1)")
done
lipo -create "${DYLIBS[@]}" -output "$FRAMEWORK/Versions/A/LibRaw"

# A framework is found through the app's rpath, not an absolute path; the
# dylib install name still points at where libtool put it.
install_name_tool -id "@rpath/LibRaw.framework/Versions/A/LibRaw" \
    "$FRAMEWORK/Versions/A/LibRaw"

cp "$WORK/install-arm64/include/libraw/"*.h "$FRAMEWORK/Versions/A/Headers/"

cat > "$FRAMEWORK/Versions/A/Modules/module.modulemap" <<'MODULEMAP'
framework module LibRaw [system] {
    textual header "libraw.h"
    export *
}
MODULEMAP

cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>LibRaw</string>
	<key>CFBundleIdentifier</key>
	<string>org.libraw.LibRaw</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>LibRaw</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>$DEPLOYMENT_TARGET</string>
</dict>
</plist>
PLIST

echo "==> Creating LibRaw.xcframework"
mkdir -p "$DEST"
rm -rf "$DEST/LibRaw.xcframework"
xcodebuild -create-xcframework \
    -framework "$FRAMEWORK" \
    -output "$DEST/LibRaw.xcframework" >/dev/null

BUILT="$DEST/LibRaw.xcframework/macos-arm64_x86_64/LibRaw.framework/Versions/A/LibRaw"
echo
echo "Built: $DEST/LibRaw.xcframework"
echo "  version: $VERSION"
echo "  archs:   $(lipo -archs "$BUILT")"
echo "  symbols: $(nm -gU "$BUILT" | wc -l | tr -d ' ')"
otool -L "$BUILT" | grep -v "^$BUILT" | sed 's/^/  links:  /'
