# Pickroom

Pickroom is a keyboard-first RAW culling workspace for macOS 14 and later. It keeps the
photograph large, makes focus inspection immediate, and keeps capture settings
visible while you decide.

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

Pickroom uses a dual decoding pipeline:

1. ImageIO/Core Image for the fastest system-native preview.
2. AppKit vector rasterization for SVG previews.
3. A bundled universal LibRaw 0.22.2 engine when the installed macOS release
   does not understand a camera or RAW variant.

The LibRaw XCFramework contains arm64 and x86_64 slices and is built for macOS
14. Source files stay in place unless the user confirms moving rejects to Trash.

LibRaw is distributed under LGPL 2.1 or CDDL 1.0. License texts are included in
`Packages/RawEngine/ThirdPartyLicenses`.
