#!/bin/bash
# Cut a Pickroom release end to end:
#   test -> universal notarised DMG -> tag -> GitHub Release -> Homebrew tap.
#
#   scripts/release.sh 0.3.0
#   scripts/release.sh 0.3.0 --dry-run
#
# The tap ships a cask, not a formula, so `brew install` hands people the same
# notarised DMG the Releases page does. A formula built from source instead,
# which sounds tidier and isn't: Homebrew's build environment cannot reach the
# login keychain, so bundle.sh finds no certificate there and falls back to
# ad-hoc — and an ad-hoc bundle gets a new identity on every rebuild, so the
# keychain items and TCC grants keyed to the old one stop matching and every
# upgrade re-asks for photo library access.
#
# The cask's `version` and `sha256` have to move together, which is the whole
# reason this is a script and not a note in the README: a stale sha means brew
# refuses to install and it reads as a Homebrew bug rather than a release
# mistake.
#
# The DMG goes out Developer ID signed and notarised so it opens without a
# detour through System Settings. bundle.sh does that work and quietly falls
# back to an ad-hoc signature when the certificate or the notarytool
# credentials are missing — fine for a local build, not for a release, which
# is why the tickets are checked below before the tag is pushed. The release
# notes promise a clean first launch; shipping an ad-hoc DMG under those notes
# would be worse than the old honest warning.
set -euo pipefail

SOURCE_REPO="zjywill/Pickroom"
TAP_REPO="zjywill/homebrew-tap"
TAP_NAME="zjywill/tap"
APP_NAME="Pickroom"
CASK="Casks/pickroom.rb"
FORMULA="Formula/pickroom.rb"
MIGRATIONS="tap_migrations.json"

die() {
    echo "error: $*" >&2
    exit 1
}

VERSION="${1:-}"
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1
[ -n "$VERSION" ] || die "usage: $(basename "$0") <MAJOR.MINOR.PATCH> [--dry-run]"
# Homebrew parses the version out of the tag; anything it cannot parse becomes
# a cask that installs under a name nobody expects.
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    die "version must be MAJOR.MINOR.PATCH, got '$VERSION'"

cd "$(dirname "$0")/.."
. "$(dirname "$0")/release-lib.sh"

TAG="v$VERSION"
REVISION="$(git rev-parse HEAD)"
BUILD="$(git rev-list --count HEAD)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Checking release state"
command -v gh >/dev/null || die "gh is not installed — 'brew install gh'"
gh auth status >/dev/null 2>&1 || die "gh is not logged in — run 'gh auth login'"
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

# A cask hands out the DMG straight off the Releases page, and GitHub only
# serves release assets anonymously for a public repository. Checked here
# rather than discovered by the first person who runs `brew install`.
VISIBILITY="$(gh repo view "$SOURCE_REPO" --json visibility -q .visibility)"
[ "$VISIBILITY" = "PUBLIC" ] ||
    die "$SOURCE_REPO is $VISIBILITY — a cask cannot download release assets from it"

# Cloned before any tag exists, so tap authentication cannot produce a release
# that is known in advance to be only half publishable.
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

# Before the tag, not after: a build that fails here costs nothing, whereas a
# failure after the push leaves a tag the release and the tap both need
# cleaning up around. VERSION is passed explicitly because bundle.sh would
# otherwise derive it from `git describe`, which cannot see a tag that does
# not exist yet.
echo "==> Building and smoke testing universal DMG"
VERSION="$VERSION" BUILD="$BUILD" SMOKE=1 scripts/bundle.sh
DMG="$PWD/dist/$APP_NAME-$VERSION.dmg"
CHECKSUM="$DMG.sha256"
[ -s "$DMG" ] || die "bundle.sh did not create $DMG"
[ -s "$CHECKSUM" ] || die "bundle.sh did not create $CHECKSUM"

# Asked again here rather than taken on bundle.sh's word: this is the last
# point before a tag is pushed, and the tag is the part that cannot be taken
# back. Both the image and the app inside it, because the image's ticket stops
# mattering the moment someone drags the app out and ejects the image.
if verify_distribution "$DMG" open && verify_dmg_contents "$DMG"; then
    NOTARISED=1
    echo "    $(du -h "$DMG" | awk '{print $1}')  $DMG  (notarised)"
elif [ "${ALLOW_UNNOTARISED:-0}" = "1" ]; then
    # Apple's notary queue can sit on a submission for hours with no verdict
    # and no incident on the status page. Shipping through that is a choice,
    # not an accident, which is why it takes an explicit flag — and why the
    # install notes below switch back to the first-launch workaround. The
    # artefact and what the notes claim about it move together or not at all.
    # scripts/notarise-release.sh backfills the tickets afterwards.
    # Pair it with NOTARIZE=0: on its own this flag is never reached,
    # because bundle.sh exits non-zero when a submission times out.
    NOTARISED=0
    echo "    $(du -h "$DMG" | awk '{print $1}')  $DMG"
    echo "    !! NOT notarised — shipping with the Gatekeeper workaround in the notes"
else
    die "$DMG has no stapled notarisation ticket. Check the Developer ID certificate and the notarytool profile, or re-run with ALLOW_UNNOTARISED=1 to ship it anyway."
fi

if [ "$DRY_RUN" = "1" ]; then
    cat <<EOF

Dry run complete. No tag, GitHub Release, or tap commit was created.

Would publish:
  tag:      $TAG
  commit:   $REVISION
  dmg:      $DMG
  notarised: $NOTARISED
  cask:     $TAP_REPO/$CASK
EOF
    exit 0
fi

echo "==> Tagging and pushing $TAG"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push -q origin "$TAG"

PREVIOUS_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
if [ -n "$PREVIOUS_TAG" ]; then
    RANGE="$PREVIOUS_TAG..$TAG"
else
    RANGE="$TAG"
fi

# Commit subjects rather than a hand-written summary: the repo writes
# conventional commits, and a changelog nobody has to write is a changelog
# that does not get skipped.
NOTES="$WORK/notes.md"
{
    echo "## Changes"
    echo
    git log --no-merges --pretty='- %s' "$RANGE"
    cat <<'NOTES'

## Install

**Homebrew (recommended)** — installs the same signed DMG straight into
/Applications:

```
brew install --cask zjywill/tap/pickroom
```

Upgrading from the old build-from-source formula? Once:

```
brew uninstall pickroom && brew install --cask zjywill/tap/pickroom
```

Already dragged Pickroom in from a DMG? A cask will not install over a copy
Homebrew did not put there — add `--force` to take it over.

NOTES
    if [ "$NOTARISED" = "1" ]; then
        cat <<'NOTES'
**DMG** — no toolchain needed. Open it, drag Pickroom to Applications, launch
it. Signed with an Apple Developer ID and notarised by Apple, so there is no
Gatekeeper detour.
NOTES
    else
        cat <<'NOTES'
**DMG** — no toolchain needed. Signed with an Apple Developer ID, but this
build is still waiting on Apple's notary service, so macOS blocks the first
launch with "Pickroom can't be opened". It only happens once:

1. Open the DMG and drag Pickroom to Applications.
2. Try to open it; macOS refuses.
3. System Settings -> Privacy & Security -> scroll down -> **Open Anyway**.

Or, in Terminal, skip the dialog entirely:

```
xattr -dr com.apple.quarantine /Applications/Pickroom.app
```
NOTES
    fi
    cat <<'NOTES'

Requires macOS 14 or later. The DMG contains a universal arm64 and x86_64 app.
NOTES
} >"$NOTES"

echo "==> Publishing GitHub Release"
gh release create "$TAG" "$DMG" "$CHECKSUM" \
    --repo "$SOURCE_REPO" \
    --title "$APP_NAME $VERSION" \
    --notes-file "$NOTES"

# The sha of the local DMG, not of a re-download: `gh release create` just
# uploaded this exact file, and hashing what we shipped is one less thing that
# can be subtly different from what people fetch.
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "    sha256 $SHA"

echo "==> Updating Homebrew tap"
cd "$WORK/tap"

# Written whole rather than sed-patched. A cask is short enough that a
# template is easier to read than three substitutions, and it means the tap
# cannot drift into a shape the next release's sed no longer matches.
mkdir -p "$(dirname "$CASK")"
cat >"$CASK" <<CASK_EOF
cask "pickroom" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$SOURCE_REPO/releases/download/v#{version}/$APP_NAME-#{version}.dmg"
  name "Pickroom"
  desc "Keyboard-first RAW culling workspace for macOS"
  homepage "https://github.com/$SOURCE_REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Bare symbol, not ">= :sonoma": Homebrew 6 reads a symbol as a minimum and
  # deprecates the string form, which every brew command then warns about.
  depends_on macos: :sonoma

  app "$APP_NAME.app"

  zap trash: [
    "~/Library/Application Support/Pickroom",
    "~/Library/Caches/Pickroom",
    "~/Library/Preferences/com.junyizhang.Pickroom.plist",
    "~/Library/Saved Application State/com.junyizhang.Pickroom.savedState",
  ]
end
CASK_EOF

# The formula and the cask cannot both answer to `pickroom`, and leaving the
# formula would keep handing new installs the ad-hoc build this cask exists to
# replace. tap_migrations.json is what tells an existing `brew upgrade` where
# the name went instead of failing with "no available formula".
if [ -f "$FORMULA" ]; then
    git rm -q "$FORMULA"
fi

# Merged, not overwritten: this tap carries other projects' migrations too,
# and rewriting the file wholesale would silently drop them.
python3 - "$MIGRATIONS" "$TAP_NAME" <<'PY'
import json, os, sys

path, tap = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path) as handle:
        data = json.load(handle)
data["pickroom"] = tap
with open(path, "w") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

git add -A
# --no-pager: in a small terminal git hands even a two-line stat to less, and
# the whole release sits at "(END)" waiting for a keypress.
git --no-pager diff --cached --stat
[ -n "$(git status --porcelain)" ] || die "tap already points at $TAG, nothing to do"
git commit -q -m "pickroom $VERSION"
git push -q origin HEAD
cd - >/dev/null

echo "==> Verifying remote release and tap"
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null
ASSET_COUNT="$(
    gh release view "$TAG" \
        --repo "$SOURCE_REPO" \
        --json assets \
        --jq '[.assets[] | select((.name == "'"$APP_NAME"'-'"$VERSION"'.dmg" or .name == "'"$APP_NAME"'-'"$VERSION"'.dmg.sha256") and .size > 0)] | length'
)"
[ "$ASSET_COUNT" = "2" ] || die "release does not contain both non-empty assets"

REMOTE_CASK="$(
    gh api -H 'Accept: application/vnd.github.raw+json' \
        "repos/$TAP_REPO/contents/$CASK"
)"
echo "$REMOTE_CASK" | grep -Fq "version \"$VERSION\"" ||
    die "remote cask does not name $VERSION"
echo "$REMOTE_CASK" | grep -Fq "sha256 \"$SHA\"" ||
    die "remote cask does not pin the published DMG"

cat <<EOF

Released $APP_NAME $VERSION.

  release  https://github.com/$SOURCE_REPO/releases/tag/$TAG
  tap      https://github.com/$TAP_REPO/blob/main/$CASK
  dmg      $DMG

Users get it with:
  brew update && brew upgrade --cask pickroom

Verify it yourself from a clean slate:
  brew uninstall --cask pickroom 2>/dev/null; brew untap $TAP_NAME
  brew install --cask $TAP_NAME/pickroom
EOF
