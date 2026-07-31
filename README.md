# Pickroom

Pickroom is a keyboard-first RAW culling workspace for macOS 14 and later. It keeps the
photograph large, makes focus inspection immediate, and keeps capture settings
visible while you decide.

## Install

### Homebrew

The source repository is private, so installing from the tap requires GitHub
SSH access to `zjywill/Pickroom`.

```bash
brew install zjywill/tap/pickroom
rm -rf /Applications/Pickroom.app
cp -R "$(brew --prefix pickroom)/Pickroom.app" /Applications/Pickroom.app
```

Quit Pickroom and repeat the copy after each upgrade.

### GitHub Release

Download the latest DMG from
[GitHub Releases](https://github.com/zjywill/Pickroom/releases), open it, and
drag Pickroom to Applications.

Pickroom is currently ad-hoc signed rather than Developer ID signed and
notarized. macOS may block the first launch after downloading the DMG. Use
**System Settings -> Privacy & Security -> Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Pickroom.app
```

## Current prototype

- Open or drag in a folder containing RAW, HEIC, TIFF, JPEG, PNG, or SVG files.
- Pair RAW and JPEG files that share a filename stem.
- Cull with `P` (pick), `M` (maybe), `X` (reject), and `U` (unmark).
- Rate by dragging across the stars or with the number keys `0` through `5`.
- Navigate with the left and right arrow keys.
- Pinch on a trackpad to zoom, then drag to inspect focus across the frame.
- Mouse users can zoom from the toolbar or double-click between fit and 200%.
- Use `Command--`, `Command-0`, and `Command-+` for zoom control.
- Inspect composition with the thirds grid (`C`).
- Switch between culling and contact sheet views with `Command-1` and `Command-2`.
- Move current rejects and paired files to macOS Trash after one explicit confirmation.
- Persist decisions locally without modifying files during normal culling.

## Build

```bash
xcodegen generate
xcodebuild -project Pickroom.xcodeproj -scheme Pickroom -configuration Debug build
```

Create a universal, ad-hoc signed app and DMG without a paid Apple Developer
account:

```bash
VERSION=0.1.0 scripts/bundle.sh
```

Import a rendered icon, remove its white background, and regenerate every
macOS AppIcon size:

```bash
Tools/import-app-icon.py /path/to/source.png
```

Pickroom uses a dual decoding pipeline:

1. ImageIO/Core Image for the fastest system-native preview.
2. AppKit vector rasterization for SVG previews.
3. A bundled universal LibRaw 0.22.2 engine when the installed macOS release
   does not understand a camera or RAW variant.

The LibRaw XCFramework contains arm64 and x86_64 slices and is built for macOS
14. Source files stay in place unless the user confirms moving rejects to Trash.

LibRaw is distributed under LGPL 2.1 or CDDL 1.0. License texts are included in
`Packages/RawEngine/ThirdPartyLicenses`.
