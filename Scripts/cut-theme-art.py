#!/usr/bin/env python3
"""Cuts a theme's art board into transparent PNGs in the app's asset catalog (Sprint 21).

Usage: python3 Scripts/cut-theme-art.py <board.png> docs/theme-art/<theme>.json

The board (an image of separate drawings on a flat background, made by the owner with a free image generator) is
never committed: only the cut drawings are. Each piece is keyed off its own crop's border color, so the drawings
work on light and dark backgrounds, then trimmed to its visible pixels. Output: one universal @3x image set per piece,
named <theme>-<piece>, under HouseholdHubApp/Resources/Assets.xcassets/ThemeArt/. Needs Pillow (local only).
"""
import json
import math
import pathlib
import sys

from PIL import Image

CATALOG = pathlib.Path("HouseholdHubApp/Resources/Assets.xcassets/ThemeArt")
FEATHER_START, FEATHER_WIDTH = 18, 50


def keyed(crop):
    width, height = crop.size
    border = [crop.getpixel((x, 0)) for x in range(width)] + [crop.getpixel((x, height - 1)) for x in range(width)]
    border += [crop.getpixel((0, y)) for y in range(height)] + [crop.getpixel((width - 1, y)) for y in range(height)]
    background = tuple(sorted(pixel[channel] for pixel in border)[len(border) // 2] for channel in range(3))
    out = Image.new("RGBA", crop.size)
    pixels = []
    for pixel in crop.getdata():
        distance = math.sqrt(sum((pixel[c] - background[c]) ** 2 for c in range(3)))
        alpha = max(0, min(255, int((distance - FEATHER_START) * 255 / FEATHER_WIDTH)))
        pixels.append((pixel[0], pixel[1], pixel[2], alpha))
    out.putdata(pixels)
    box = out.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    return out.crop(box) if box else out


def main(board_path, spec_path):
    spec = json.loads(pathlib.Path(spec_path).read_text())
    board = Image.open(board_path).convert("RGB")
    expected = (spec["board"]["width"], spec["board"]["height"])
    if board.size != expected:
        sys.exit(f"Board is {board.size}, the crop boxes are for {expected}")
    for left, top, right, bottom in spec.get("clear", []):
        # Areas that are not art (e.g. a status bar), painted with the color just below them.
        fill = board.getpixel((left, bottom + 2))
        board.paste(fill, (left, top, right, bottom))
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for name, box in spec["pieces"].items():
        asset = f"{spec['theme']}-{name}"
        folder = CATALOG / f"{asset}.imageset"
        folder.mkdir(exist_ok=True)
        keyed(board.crop(tuple(box))).save(folder / f"{asset}.png", optimize=True)
        contents = {
            "images": [{"filename": f"{asset}.png", "idiom": "universal", "scale": "3x"}],
            "info": {"author": "xcode", "version": 1},
        }
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        print(asset)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
