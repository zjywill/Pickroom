#!/usr/bin/env python3
"""Render Pickroom's SVG artwork into every macOS AppIcon asset size.

Requires `rsvg-convert` from librsvg:
    brew install librsvg

Usage:
    Tools/render-app-icon.py [Artwork/PickroomIcon.svg] [AppIcon.appiconset]
"""

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

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


def render_svg(source):
    with tempfile.NamedTemporaryFile(suffix=".png") as rendered:
        subprocess.run(
            [
                "rsvg-convert",
                "--width",
                "1024",
                "--height",
                "1024",
                "--output",
                rendered.name,
                str(source),
            ],
            check=True,
        )
        return Image.open(rendered.name).convert("RGBA")


def main():
    source = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path("Artwork/PickroomIcon.svg")
    )
    output_dir = (
        Path(sys.argv[2])
        if len(sys.argv) > 2
        else Path("Pickroom/Assets.xcassets/AppIcon.appiconset")
    )

    if not source.is_file():
        raise SystemExit(f"No SVG artwork at {source}")

    master = render_svg(source)
    output_dir.mkdir(parents=True, exist_ok=True)

    for size, filename in ICON_FILES:
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            output_dir / filename
        )

    print(f"rendered {source} into {len(ICON_FILES)} icons at {output_dir}")


if __name__ == "__main__":
    main()
