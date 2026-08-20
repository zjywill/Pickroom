---
name: release
description: >-
  Manual-only Pickroom release workflow. Invoke explicitly with /release to
  test, build, Developer ID sign and notarize the universal macOS app, publish
  the GitHub Release, and update the Homebrew cask.
disable-model-invocation: true
---

# Releasing Pickroom

This skill is manual-only. Do not invoke it from release-shaped conversation;
the user must explicitly run `/release`.

One command owns the release:

```bash
scripts/release.sh <MAJOR.MINOR.PATCH>
```

It verifies clean and synchronized `main`, verifies the source repository is
public (a cask cannot download assets from a private one), runs the Xcode
tests, builds and smoke launches a universal app, signs it with the Developer
ID, notarizes and staples the app and the DMG, writes the SHA-256 file, pushes
`v<version>`, publishes both assets on GitHub Releases, rewrites the cask in
`zjywill/homebrew-tap`, and verifies both remote surfaces.

Use `--dry-run` as the second argument to run everything up to and including
notarization without creating a tag, Release, or tap commit. Note that a dry
run costs a full notary round trip and the real run then rebuilds — a rebuild
is a different cdhash, so the ticket does not carry over. Prefer
`NOTARIZE=0 DMG=0 scripts/bundle.sh` when the thing being checked is the build
rather than the release plumbing.

## Version

```bash
git describe --tags --abbrev=0
```

- New features: bump MINOR.
- Fixes only: bump PATCH.
- Breaking changes: bump MAJOR.

The git tag is the release version. `bundle.sh` writes the requested value to
`CFBundleShortVersionString`; the git commit count becomes `CFBundleVersion`.

## Signing And Notarization

`scripts/bundle.sh` picks the tier the machine can do. With a "Developer ID
Application" certificate in the keychain it signs with `--options runtime` and
a secure timestamp, inside out — nested dylibs, then frameworks, then the app —
because signing a bundle's nested code after its container invalidates the
container. Without a certificate it falls back to ad-hoc, which is fine
locally and is not shippable.

**Two tickets, not one.** A ticket on the DMG covers the DMG. Drag the app to
Applications, eject the image, and what Gatekeeper reads on a Mac that is
offline is the ticket inside the bundle. So the app is notarized and stapled
before it goes into the image, and the image is notarized and stapled after.

**Verification is the part that is easy to get wrong.** `codesign --verify`
passes on an ad-hoc bundle and on a Developer ID bundle Apple has never seen;
`spctl --assess` asks Apple over the network, so it waves through a build whose
ticket exists on Apple's servers but was never stapled to the file. The two
checks that read the ticket inside the file are `xcrun stapler validate` and
`syspolicy_check distribution`. `verify_distribution()` in
`scripts/release-lib.sh` runs all four, and `release.sh` re-runs it on the DMG
and on the app inside the DMG before the tag is pushed. Do not weaken that
gate: the tag is the part that cannot be taken back.

Release notes must not carry the **Open Anyway** or
`xattr -dr com.apple.quarantine` instructions for a notarized build. The
artefact and what the notes claim about it move together.

## When Apple's Notary Queue Stalls

Verdicts for this Developer ID have taken hours, with no incident on Apple's
status page. A resubmission does not jump the queue, it adds one more item to a
slow one, which is why `NOTARY_TIMEOUT` defaults to 2h and `NOTARY_RETRIES` to
1. Do not shorten them to "get past it faster".

Ctrl-C is safe. The submission survives, Apple keeps the ticket keyed to the
cdhash, and `notarise()` tries `stapler staple` before queueing, so a re-run
picks up a waiting ticket in about a second.

When a release cannot wait, ship it and backfill:

```bash
ALLOW_UNNOTARISED=1 scripts/release.sh X.Y.Z    # notes carry the workaround
scripts/notarise-release.sh X.Y.Z               # run repeatedly, ~3 times
```

`notarise-release.sh` never waits and never resubmits what is already queued.
It downloads the DMG that actually shipped rather than rebuilding, gets both
tickets onto it, replaces the Release assets, repoints the cask's `sha256`, and
strips the workaround out of the notes.

## Homebrew Boundary

The tap ships **`Casks/pickroom.rb`**, not a formula, so `brew install` hands
people the same notarized DMG the Releases page does.

Do not move back to a build-from-source formula. Homebrew's build environment
cannot reach the login keychain, so `bundle.sh` finds no certificate there and
falls back to ad-hoc — and an ad-hoc identity changes on every rebuild, so the
keychain items and TCC grants keyed to the old one stop matching and every
upgrade re-asks for photo library access.

A cask can only fetch release assets from a **public** repository. `release.sh`
checks this before it builds anything.

`tap_migrations.json` maps the retired `pickroom` formula name to
`zjywill/tap`. The tap carries other projects' migrations too, so `release.sh`
merges that file rather than rewriting it.

The cask's `version` and `sha256` move together. A stale `sha256` makes brew
refuse to install and reads as a Homebrew bug rather than a release mistake.

## Remote Verification

For `X.Y.Z`, confirm all three surfaces:

```bash
git ls-remote --tags origin | grep vX.Y.Z
gh release view vX.Y.Z --repo zjywill/Pickroom --json tagName,assets
gh api -H 'Accept: application/vnd.github.raw+json' \
  repos/zjywill/homebrew-tap/contents/Casks/pickroom.rb |
  grep -E 'version|sha256'
```

The Release must contain non-empty `Pickroom-X.Y.Z.dmg` and
`Pickroom-X.Y.Z.dmg.sha256` assets, and the cask's `sha256` must equal the
published DMG's.

Check the ticket the way a downloader's Mac will — reading the file rather than
asking Apple:

```bash
gh release download vX.Y.Z --repo zjywill/Pickroom --pattern '*.dmg' \
  --dir /tmp/vX.Y.Z --clobber
xcrun stapler validate /tmp/vX.Y.Z/Pickroom-X.Y.Z.dmg
```

Then the user path:

```bash
brew update && brew upgrade --cask pickroom
```

## Failure Recovery

**Tag pushed, Release missing:** build the exact version again and create the
Release without moving the tag. The rebuild is a new cdhash, so it needs its
own tickets:

```bash
VERSION=X.Y.Z BUILD="$(git rev-list --count vX.Y.Z)" scripts/bundle.sh
gh release create vX.Y.Z \
  dist/Pickroom-X.Y.Z.dmg \
  dist/Pickroom-X.Y.Z.dmg.sha256 \
  --repo zjywill/Pickroom
```

**Release exists, assets missing:** upload them in place with `--clobber`. If
the DMG changed, the cask's `sha256` has to change with it.

**Release exists, cask is old:** do not recreate the Release. Edit
`Casks/pickroom.rb` in `zjywill/homebrew-tap` to the published version and the
published DMG's `sha256`, then push only the tap.

**Release shipped without tickets:** `scripts/notarise-release.sh X.Y.Z`, run
until it stops telling you to come back. Do not cut a new version for this —
the binary is unchanged, only the tickets are new.

**Homebrew still reports an old version:** inspect the remote cask through the
GitHub API before blaming local cache, then run `brew update`.
