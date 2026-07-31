#!/bin/bash
# Cut a Pickroom release end to end:
#   test -> universal ad-hoc DMG -> tag -> GitHub Release -> Homebrew tap.
#
#   scripts/release.sh 0.1.0
#   scripts/release.sh 0.1.0 --dry-run
#
# The source repository is currently private. The Homebrew formula therefore
# fetches its exact tag and revision over SSH instead of using GitHub's public
# tarball URL. Users installing from the tap need SSH access to the repo.
set -euo pipefail

SOURCE_REPO="zjywill/Pickroom"
TAP_REPO="zjywill/homebrew-tap"
TAP_NAME="zjywill/tap"
FORMULA_NAME="pickroom"
FORMULA="Formula/pickroom.rb"
FORMULA_TEMPLATE="Packaging/homebrew/pickroom.rb"

die() {
    echo "error: $*" >&2
    exit 1
}

VERSION="${1:-}"
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1
[ -n "$VERSION" ] || die "usage: $(basename "$0") <MAJOR.MINOR.PATCH> [--dry-run]"
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    die "version must be MAJOR.MINOR.PATCH, got '$VERSION'"

cd "$(dirname "$0")/.."
TAG="v$VERSION"
REVISION="$(git rev-parse HEAD)"
BUILD="$(git rev-list --count HEAD)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Checking release state"
command -v gh >/dev/null || die "gh is not installed"
command -v brew >/dev/null || die "Homebrew is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not logged in"
[ -f "$FORMULA_TEMPLATE" ] || die "$FORMULA_TEMPLATE is missing"
[ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit it first"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "release must run from main"
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
    die "main and origin/main differ; push or pull first"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null &&
    die "$TAG already exists locally"
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 &&
    die "$TAG already exists on origin"
gh release view "$TAG" --repo "$SOURCE_REPO" >/dev/null 2>&1 &&
    die "GitHub Release $TAG already exists"

if ! brew tap | grep -Fxq "$TAP_NAME"; then
    brew tap "$TAP_NAME"
fi
LOCAL_TAP="$(brew --repo "$TAP_NAME")"
[ -d "$LOCAL_TAP/.git" ] || die "Homebrew tap checkout is missing: $LOCAL_TAP"
[ -z "$(git -C "$LOCAL_TAP" status --porcelain)" ] ||
    die "Homebrew tap checkout is dirty: $LOCAL_TAP"
git -C "$LOCAL_TAP" fetch -q origin
git -C "$LOCAL_TAP" merge --ff-only -q origin/main ||
    die "Homebrew tap checkout cannot fast-forward to origin/main"

# Clone before creating any tag so tap authentication cannot produce a
# release that is known in advance to be only half publishable.
git clone -q "git@github.com:$TAP_REPO.git" "$WORK/tap"

echo "==> Running test suite"
TEST_LOG="$WORK/xcodebuild-test.log"
if ! xcodebuild \
    -project Pickroom.xcodeproj \
    -scheme Pickroom \
    -configuration Debug \
    -destination "platform=macOS" \
    test >"$TEST_LOG" 2>&1; then
    tail -80 "$TEST_LOG" >&2
    die "test suite failed"
fi
grep -E 'Executed [0-9]+ tests, with 0 failures|\*\* TEST SUCCEEDED \*\*' "$TEST_LOG" |
    tail -4

echo "==> Building and smoke testing universal DMG"
VERSION="$VERSION" BUILD="$BUILD" SMOKE=1 scripts/bundle.sh
DMG="$PWD/dist/Pickroom-$VERSION.dmg"
CHECKSUM="$DMG.sha256"
[ -s "$DMG" ] || die "bundle.sh did not create $DMG"
[ -s "$CHECKSUM" ] || die "bundle.sh did not create $CHECKSUM"

if [ "$DRY_RUN" = "1" ]; then
    cat <<EOF

Dry run complete. No tag, GitHub Release, or tap commit was created.

Would publish:
  tag:     $TAG
  commit:  $REVISION
  dmg:     $DMG
  formula: $TAP_REPO/$FORMULA
EOF
    exit 0
fi

echo "==> Tagging and pushing $TAG"
git tag -a "$TAG" -m "Pickroom $VERSION"
git push -q origin "$TAG"

PREVIOUS_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
if [ -n "$PREVIOUS_TAG" ]; then
    RANGE="$PREVIOUS_TAG..$TAG"
else
    RANGE="$TAG"
fi

NOTES="$WORK/notes.md"
{
    echo "## Changes"
    echo
    git log --no-merges --pretty='- %s' "$RANGE"
    cat <<'NOTES'

## Install

### Homebrew

The source repository is private, so the tap install requires GitHub SSH
access to `zjywill/Pickroom`.

```bash
brew install zjywill/tap/pickroom
rm -rf /Applications/Pickroom.app
cp -R "$(brew --prefix pickroom)/Pickroom.app" /Applications/Pickroom.app
```

### DMG

Download the DMG, open it, and drag Pickroom to Applications. Pickroom is
ad-hoc signed because it does not yet use a paid Apple Developer account.
The signature protects bundle integrity, but the app is not notarized, so
macOS may block the first launch.

Use **System Settings -> Privacy & Security -> Open Anyway**, or remove the
download quarantine in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Pickroom.app
```

Requires macOS 14 or later. The DMG contains a universal arm64 and x86_64 app.
NOTES
} >"$NOTES"

echo "==> Publishing GitHub Release"
gh release create "$TAG" "$DMG" "$CHECKSUM" \
    --repo "$SOURCE_REPO" \
    --title "Pickroom $VERSION" \
    --notes-file "$NOTES"

echo "==> Updating Homebrew tap"
/usr/bin/sed \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__REVISION__/$REVISION/g" \
    "$FORMULA_TEMPLATE" >"$WORK/tap/$FORMULA"

cd "$WORK/tap"
git --no-pager diff --stat -- "$FORMULA"
git add "$FORMULA"
[ -n "$(git status --porcelain)" ] || die "$FORMULA did not change"
git commit -q -m "pickroom $VERSION"
git push -q origin HEAD
cd - >/dev/null

echo "==> Verifying remote release and tap"
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null
ASSET_COUNT="$(
    gh release view "$TAG" \
        --repo "$SOURCE_REPO" \
        --json assets \
        --jq '[.assets[] | select((.name == "Pickroom-'"$VERSION"'.dmg" or .name == "Pickroom-'"$VERSION"'.dmg.sha256") and .size > 0)] | length'
)"
[ "$ASSET_COUNT" = "2" ] || die "release does not contain both non-empty assets"

REMOTE_FORMULA="$(
    gh api -H 'Accept: application/vnd.github.raw+json' \
        "repos/$TAP_REPO/contents/$FORMULA"
)"
echo "$REMOTE_FORMULA" | grep -Eq "tag:[[:space:]]+\"$TAG\"" ||
    die "remote formula does not name $TAG"
echo "$REMOTE_FORMULA" | grep -Eq "revision:[[:space:]]+\"$REVISION\"" ||
    die "remote formula does not pin $REVISION"

echo "==> Verifying Homebrew install"
git -C "$LOCAL_TAP" fetch -q origin
git -C "$LOCAL_TAP" merge --ff-only -q origin/main ||
    die "Homebrew tap checkout cannot fast-forward to the published formula"
[ "$(git -C "$LOCAL_TAP" rev-parse HEAD)" = "$(git -C "$LOCAL_TAP" rev-parse origin/main)" ] ||
    die "Homebrew tap checkout and origin/main differ after synchronization"

FORMULA_REF="$TAP_NAME/$FORMULA_NAME"
if brew list --versions "$FORMULA_NAME" >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall --build-from-source "$FORMULA_REF"
else
    HOMEBREW_NO_AUTO_UPDATE=1 brew install --build-from-source "$FORMULA_REF"
fi
brew test "$FORMULA_REF"

INSTALLED_APP="$(brew --prefix "$FORMULA_NAME")/Pickroom.app"
INSTALLED_VERSION="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$INSTALLED_APP/Contents/Info.plist"
)"
[ "$INSTALLED_VERSION" = "$VERSION" ] ||
    die "Homebrew installed version $INSTALLED_VERSION instead of $VERSION"
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"

cat <<EOF

Released Pickroom $VERSION.

  release: https://github.com/$SOURCE_REPO/releases/tag/$TAG
  tap:     https://github.com/$TAP_REPO/blob/main/$FORMULA
  dmg:     $DMG

Install or upgrade:
  brew update
  brew upgrade pickroom || brew install zjywill/tap/pickroom
EOF
