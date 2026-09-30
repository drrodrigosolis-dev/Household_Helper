#!/usr/bin/env python3
"""Cuts a theme's art boards into transparent PNGs in the app's asset catalog (Sprint 21).

Usage: python3 Scripts/cut-theme-art.py docs/theme-art/<theme>.json <board>=<image.png> [<board>=<image.png> ...]

A board is an image of separate drawings on a flat background, made by the owner with a free image generator. Boards
are never committed: only the cut drawings are. The spec names each board with its pixel size, and each piece (a role
the app draws: `header1`, `cornerTopLeading`, ... see `ThemePiece` in ThemeArt.swift) with a crop box, as
`[left, top, right, bottom]` on the first board or `{"board": name, "box": [...], "fill": true, "isolate": true}`.
A piece is keyed off its own crop's border color, so the drawings work on light and dark backgrounds; `fill` keeps
enclosed paper-colored areas opaque (white bodies); `isolate` keeps only the largest drawing in the crop (for
drawings that touch a neighbour); then it is trimmed to its visible pixels.
Output: one universal @3x image set per piece, named <theme>-<piece>, under
HouseholdHubApp/Resources/Assets.xcassets/ThemeArt/. Stale image sets of the theme are removed. Needs Pillow (local).
"""
import json
import math
import pathlib
import shutil
import sys
from collections import deque

from PIL import Image, ImageFilter

CATALOG = pathlib.Path("HouseholdHubApp/Resources/Assets.xcassets/ThemeArt")
FEATHER_START, FEATHER_WIDTH = 18, 50
VISIBLE = 24
# Isolation works on a half-size mask grown by this many pixels, so a drawing's separate strokes stay together.
ISOLATE_GROW = 3
# Outline gaps up to twice this many pixels are closed when filling a white body.
FILL_CLOSE = 3


def keyed(crop):
    width, height = crop.size
    border = [crop.getpixel((x, 0)) for x in range(width)] + [crop.getpixel((x, height - 1)) for x in range(width)]
    border += [crop.getpixel((0, y)) for y in range(height)] + [crop.getpixel((width - 1, y)) for y in range(height)]
    background = tuple(sorted(pixel[channel] for pixel in border)[len(border) // 2] for channel in range(3))
    out = Image.new("RGBA", crop.size)
    pixels = []
    for y in range(height):
        for x in range(width):
            pixel = crop.getpixel((x, y))
            distance = math.sqrt(sum((pixel[c] - background[c]) ** 2 for c in range(3)))
            alpha = max(0, min(255, int((distance - FEATHER_START) * 255 / FEATHER_WIDTH)))
            pixels.append((pixel[0], pixel[1], pixel[2], alpha))
    out.putdata(pixels)
    return out


def filled(image, close=None):
    """Makes enclosed background opaque: a white body (a jet, a snowman) is paper-colored inside its outline and would
    otherwise turn see-through on the dark theme. Background reachable from the crop's edge stays transparent.
    Strokes are grown by `close` pixels (FILL_CLOSE by default) while finding the outside, so small gaps in an
    outline don't leak, and the outside is grown back by as much, so no paper halo is left around the drawing."""
    close = close or FILL_CLOSE
    width, height = image.size
    strokes = image.getchannel("A").point(lambda a: 255 if a > VISIBLE else 0)
    walls = strokes.filter(ImageFilter.MaxFilter(2 * close + 1)).load()
    outside = Image.new("L", image.size, 0)
    marks = outside.load()
    queue = deque()
    for x in range(width):
        queue.extend([(x, 0), (x, height - 1)])
    for y in range(height):
        queue.extend([(0, y), (width - 1, y)])
    while queue:
        x, y = queue.popleft()
        if marks[x, y] or walls[x, y]:
            continue
        marks[x, y] = 255
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height and not marks[nx, ny]:
                queue.append((nx, ny))
    reach = outside.filter(ImageFilter.MaxFilter(2 * close + 1)).load()
    data = image.load()
    for y in range(height):
        for x in range(width):
            if not reach[x, y]:
                r, g, b, _ = data[x, y]
                data[x, y] = (r, g, b, 255)
    return image


def isolated(image):
    """Keeps the largest group of strokes; everything else in the crop becomes transparent."""
    alpha = image.getchannel("A")
    small = alpha.resize((max(1, image.width // 2), max(1, image.height // 2)), Image.BOX)
    mask = small.point(lambda a: 255 if a > VISIBLE else 0).filter(ImageFilter.MaxFilter(ISOLATE_GROW))
    width, height = mask.size
    pixels = mask.load()
    label = {}
    sizes = []
    for y in range(height):
        for x in range(width):
            if not pixels[x, y] or (x, y) in label:
                continue
            index = len(sizes)
            queue = deque([(x, y)])
            label[(x, y)] = index
            count = 0
            while queue:
                cx, cy = queue.popleft()
                count += 1
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and pixels[nx, ny] and (nx, ny) not in label:
                        label[(nx, ny)] = index
                        queue.append((nx, ny))
            sizes.append(count)
    if not sizes:
        return image
    keep = max(range(len(sizes)), key=sizes.__getitem__)
    out = image.copy()
    data = out.load()
    for y in range(image.height):
        for x in range(image.width):
            if label.get((min(x // 2, width - 1), min(y // 2, height - 1))) != keep:
                r, g, b, _ = data[x, y]
                data[x, y] = (r, g, b, 0)
    return out


def trimmed(image):
    box = image.getchannel("A").point(lambda a: 255 if a > VISIBLE else 0).getbbox()
    return image.crop(box) if box else image


def main(spec_path, board_args):
    spec = json.loads(pathlib.Path(spec_path).read_text())
    theme = spec["theme"]
    paths = dict(argument.split("=", 1) for argument in board_args)
    boards = {}
    for name, info in spec["boards"].items():
        if name not in paths:
            sys.exit(f"Missing {name}=<image.png>")
        board = Image.open(paths[name]).convert("RGB")
        if board.size != (info["width"], info["height"]):
            sys.exit(f"Board {name} is {board.size}, the crop boxes are for {(info['width'], info['height'])}")
        for left, top, right, bottom in info.get("clear", []):
            # Areas that are not art (e.g. a status bar), painted with the color just below them.
            board.paste(board.getpixel((left, bottom + 2)), (left, top, right, bottom))
        boards[name] = board
    first = next(iter(spec["boards"]))
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for stale in CATALOG.glob(f"{theme}-*.imageset"):
        shutil.rmtree(stale)
    for name, piece in spec["pieces"].items():
        if isinstance(piece, list):
            piece = {"box": piece}
        image = keyed(boards[piece.get("board", first)].crop(tuple(piece["box"])))
        if piece.get("fill"):
            # `true`, or how many pixels of outline gap to close for a looser drawing.
            fill = piece["fill"]
            image = filled(image, fill if isinstance(fill, int) and not isinstance(fill, bool) else None)
        if piece.get("isolate"):
            image = isolated(image)
        asset = f"{theme}-{name}"
        folder = CATALOG / f"{asset}.imageset"
        folder.mkdir()
        trimmed(image).save(folder / f"{asset}.png", optimize=True)
        contents = {
            "images": [{"filename": f"{asset}.png", "idiom": "universal", "scale": "3x"}],
            "info": {"author": "xcode", "version": 1},
        }
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        print(asset)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
