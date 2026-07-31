#!/usr/bin/env python3
"""Crop a rendered Pickroom icon, remove its white matte, and build an iconset.

The source artwork is expected to contain a dark rounded-square app icon on a
light background. The script finds the outer dark silhouette row by row,
reconstructs its anti-aliased black edge without a white halo, normalizes it to
Apple's 824 px icon grid, and writes every macOS AppIcon asset size.

Usage:
    Tools/import-app-icon.py <source.png> [AppIcon.appiconset]
"""

import sys
from pathlib import Path

from PIL import Image

CANVAS_SIZE = 1024
SHAPE_SIZE = 824
SHAPE_OFFSET = (CANVAS_SIZE - SHAPE_SIZE) // 2
EDGE_LUMINANCE = 220
OPAQUE_LUMINANCE = 80
BACKGROUND_CHANNEL = 254.0
BLACK_CHANNEL = 15.0

ICON_FILES = (
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
)


def luminance(pixel):
    return sum(pixel) / 3


def extract_silhouette(source):
    width, height = source.size
    source_pixels = source.load()
    alpha_mask = Image.new("L", source.size, 0)
    alpha_pixels = alpha_mask.load()
    extracted = Image.new("RGBA", source.size, (0, 0, 0, 0))
    extracted_pixels = extracted.load()

    for y in range(height):
        row = [luminance(source_pixels[x, y]) for x in range(width)]
        edge = [x for x, value in enumerate(row) if value < EDGE_LUMINANCE]
        if not edge:
            continue

        opaque = [x for x, value in enumerate(row) if value < OPAQUE_LUMINANCE]
        edge_left, edge_right = edge[0], edge[-1]
        if opaque:
            opaque_left, opaque_right = opaque[0], opaque[-1]
        else:
            opaque_left, opaque_right = edge_right + 1, edge_left - 1

        for x in range(edge_left, edge_right + 1):
            if opaque_left <= x <= opaque_right:
                alpha = 255
                color = source_pixels[x, y]
            else:
                # The outside silhouette is black composited over white.
                # Recover its coverage and store a clean black edge so the
                # original white matte cannot appear on dark wallpapers.
                darkest = min(source_pixels[x, y])
                coverage = (BACKGROUND_CHANNEL - darkest) / (
                    BACKGROUND_CHANNEL - BLACK_CHANNEL
                )
                alpha = round(max(0.0, min(1.0, coverage)) * 255)
                color = (8, 8, 8)

            alpha_pixels[x, y] = alpha
            extracted_pixels[x, y] = (*color, alpha)

    bounds = alpha_mask.getbbox()
    if bounds is None:
        raise SystemExit("No dark icon silhouette found in the source image")

    return extracted.crop(bounds), bounds


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)

    source_path = Path(sys.argv[1])
    output_dir = (
        Path(sys.argv[2])
        if len(sys.argv) > 2
        else Path("Pickroom/Assets.xcassets/AppIcon.appiconset")
    )

    source = Image.open(source_path).convert("RGB")
    shape, bounds = extract_silhouette(source)
    shape = shape.resize((SHAPE_SIZE, SHAPE_SIZE), Image.Resampling.LANCZOS)

    master = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    master.alpha_composite(shape, (SHAPE_OFFSET, SHAPE_OFFSET))

    output_dir.mkdir(parents=True, exist_ok=True)
    for size, filename in ICON_FILES:
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            output_dir / filename
        )

    print(
        f"cropped {source.size} source at {bounds}; "
        f"wrote {len(ICON_FILES)} icons to {output_dir}"
    )


if __name__ == "__main__":
    main()
