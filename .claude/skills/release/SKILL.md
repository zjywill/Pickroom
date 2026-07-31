---
name: release
description: >-
  Manual-only Pickroom release workflow. Invoke explicitly with /release to
  test, build and ad-hoc sign the universal macOS app, publish the GitHub
  Release, and update the Homebrew tap.
disable-model-invocation: true
---

# Releasing Pickroom

This skill is manual-only. Do not invoke it from release-shaped conversation;
the user must explicitly run `/release`.

One command owns the release:

```bash
scripts/release.sh <MAJOR.MINOR.PATCH>
```

It verifies clean and synchronized `main`, runs the Xcode tests, builds and
smoke launches a universal app, ad-hoc signs the app and its nested frameworks,
creates a DMG plus SHA-256 file, pushes `v<version>`, publishes both assets on
GitHub Releases, updates `zjywill/homebrew-tap`, and verifies both remote
surfaces.

Use `--dry-run` as the second argument to run the test/build/sign/smoke checks
without creating a tag, Release, or tap commit:

```bash
scripts/release.sh 0.1.0 --dry-run
```

## Version

```bash
git describe --tags --abbrev=0
```

- New features: bump MINOR.
- Fixes only: bump PATCH.
- Breaking changes: bump MAJOR.
- No existing tag: start at `0.1.0`.

The git tag is the release version. `bundle.sh` writes the requested value to
`CFBundleShortVersionString`; the git commit count becomes `CFBundleVersion`.

## Signing Boundary

Pickroom currently has no paid Apple Developer account. `scripts/bundle.sh`
therefore uses ad-hoc signing (`codesign --sign -`) and signs nested dylibs and
frameworks before the outer app. This proves bundle integrity but is not
Developer ID distribution and is not notarization.

Downloaded DMGs are quarantined. Release notes must retain the **Open Anyway**
and `xattr -dr com.apple.quarantine /Applications/Pickroom.app` instructions
until Developer ID signing and notarization are actually implemented.

## Homebrew Boundary

The source repository is private. The formula intentionally fetches:

```ruby
url "git@github.com:zjywill/Pickroom.git",
    tag: "v<version>",
    revision: "<exact commit>"
```

Do not replace this with a public GitHub tarball URL while the repo remains
private. Tap users need SSH access to the source repository. The formula builds
from source, so its app does not carry download quarantine.

After installation, put a real app copy in Applications:

```bash
rm -rf /Applications/Pickroom.app
cp -R "$(brew --prefix pickroom)/Pickroom.app" /Applications/Pickroom.app
```

Quit Pickroom before replacing the copy.

## Remote Verification

For `X.Y.Z`, confirm all three surfaces:

```bash
git ls-remote --tags origin | grep vX.Y.Z
gh release view vX.Y.Z --repo zjywill/Pickroom --json tagName,assets
gh api -H 'Accept: application/vnd.github.raw+json' \
  repos/zjywill/homebrew-tap/contents/Formula/pickroom.rb |
  grep -E 'tag:|revision:'
```

The Release must contain non-empty `Pickroom-X.Y.Z.dmg` and
`Pickroom-X.Y.Z.dmg.sha256` assets. The formula must name the same tag and the
tagged commit revision.

Then verify the user path:

```bash
brew update
brew install --build-from-source zjywill/tap/pickroom
brew test zjywill/tap/pickroom
```

## Failure Recovery

**Tag pushed, Release missing:** build the exact version again and create the
Release without moving the tag:

```bash
VERSION=X.Y.Z BUILD="$(git rev-list --count vX.Y.Z)" scripts/bundle.sh
gh release create vX.Y.Z \
  dist/Pickroom-X.Y.Z.dmg \
  dist/Pickroom-X.Y.Z.dmg.sha256 \
  --repo zjywill/Pickroom
```

**Release exists, assets missing:** upload them in place:

```bash
gh release upload vX.Y.Z \
  dist/Pickroom-X.Y.Z.dmg \
  dist/Pickroom-X.Y.Z.dmg.sha256 \
  --repo zjywill/Pickroom \
  --clobber
```

**Release exists, tap is old:** do not recreate the Release. Generate
`Formula/pickroom.rb` from `Packaging/homebrew/pickroom.rb`, replacing
`__VERSION__` and `__REVISION__`, then commit and push only the tap.

**Homebrew still reports an old version:** inspect the remote formula through
the GitHub API before blaming local cache, then run `brew update`. A copied app
in `/Applications` must be refreshed after every upgrade.
