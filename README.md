# Pickroom

Pickroom is a keyboard-first RAW culling workspace for macOS 14 and later. It keeps the
photograph large, makes focus inspection immediate, and keeps capture settings
visible while you decide.

## Install

### Homebrew

The cask installs the same signed DMG the Releases page serves, straight into
Applications.

```bash
brew install --cask zjywill/tap/pickroom
```

Upgrading from the old build-from-source formula? Once:

```bash
brew uninstall pickroom && brew install --cask zjywill/tap/pickroom
```

### GitHub Release

Download the latest DMG from
[GitHub Releases](https://github.com/zjywill/Pickroom/releases), open it, and
drag Pickroom to Applications.

The DMG and the app inside it are signed with an Apple Developer ID and
notarized by Apple, so there is no Gatekeeper detour on first launch.

## Current prototype

- Open or drag in a folder containing RAW, HEIC, TIFF, JPEG, PNG, or SVG files.
- Or open the system photo library (`Shift-Command-O`) and cull albums, smart
  albums, and All Photos, including iCloud photos.
- Pair RAW and JPEG files that share a filename stem.
- Cull with `P` (pick), `M` (maybe), `X` (reject), and `U` (unmark).
- Rate by dragging across the stars or with the number keys `0` through `5`.
- Navigate with the left and right arrow keys.
- Pinch on a trackpad to zoom, then drag to inspect focus across the frame.
- Mouse users can zoom from the toolbar or double-click between fit and 200%.
- Use `Command--`, `Command-0`, and `Command-+` for zoom control.
- Press `Space` to switch between fit to window and 100% pixels.
- Inspect composition with the thirds grid (`C`).
- Switch between culling and contact sheet views with `Command-1` and `Command-2`.
- Move current rejects and paired files to macOS Trash after one explicit confirmation.
  In the photo library, rejects go to Recently Deleted instead, and Photos asks
  for its own confirmation.
- Persist decisions locally without modifying files during normal culling.

### iCloud photos stay in iCloud

Browsing the photo library never downloads anything. Previews come from the
renders Photos already keeps on this Mac, so grids, filmstrips, fit-to-window,
and pick/reject decisions all work offline.

An iCloud-only photo cannot be inspected at 1:1 and has no capture settings
until its original is on this Mac, so Pickroom shows a badge and waits. Press
`Command-D` — or use the toolbar button — to download that one original. Nothing
is prefetched, batched, or downloaded in the background. Downloads land in
`~/Library/Caches/Pickroom/Originals` and are decoded by the normal ImageIO and
LibRaw pipeline.

## Build

```bash
xcodegen generate
xcodebuild -project Pickroom.xcodeproj -scheme Pickroom -configuration Debug build
```

Create a universal app and DMG:

```bash
VERSION=0.3.0 scripts/bundle.sh
```

`bundle.sh` picks whichever signing tier the machine can do. With a "Developer
ID Application" certificate in the keychain it signs with the hardened runtime
and a secure timestamp, then notarizes the app and the DMG and staples both
tickets. Without one it falls back to an ad-hoc signature, which runs locally
but is refused by Gatekeeper after a download. `SIGN_ID=-` forces ad-hoc and
`NOTARIZE=0` skips Apple's notary service.

Cutting a release — tests, notarized DMG, tag, GitHub Release, and the
Homebrew cask — is one command:

```bash
scripts/release.sh 0.3.0 --dry-run
scripts/release.sh 0.3.0
```

Apple's notary queue can sit on a submission for hours. When it does, ship
with `ALLOW_UNNOTARISED=1` and backfill the tickets afterwards by re-running
`scripts/notarise-release.sh 0.3.0` until it stops telling you to come back;
it replaces the published DMG, repoints the cask, and strips the Gatekeeper
workaround from the release notes.

The app icon is maintained as the Icon Composer project at
`Pickroom/AppIcon.icon`.

Pickroom uses a dual decoding pipeline:

1. ImageIO/Core Image for the fastest system-native preview.
2. AppKit vector rasterization for SVG previews.
3. A bundled universal LibRaw 0.22.2 engine when the installed macOS release
   does not understand a camera or RAW variant.

The LibRaw XCFramework contains arm64 and x86_64 slices and is built for macOS
14. Source files stay in place unless the user confirms moving rejects to Trash.

LibRaw is distributed under LGPL 2.1 or CDDL 1.0. License texts are included in
`Packages/RawEngine/ThirdPartyLicenses`.
