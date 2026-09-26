#!/usr/bin/env python3
"""Turn a verify.yml artifact zip into the walk record: downscaled JPEGs plus light/dark/large-text contact sheets.

Usage: python3 Scripts/walk-screens.py <artifact.zip> <output dir>   (needs Pillow: pip install pillow)
Screenshots are named "<variant>-<Screen>.png" by the UI tests (see HouseholdHubUITests/WalkSupport.swift).
"""
import io
import pathlib
import sys
import zipfile

from PIL import Image

WIDTH = 360
VARIANTS = ["light", "dark", "largeText"]


def main() -> None:
    archive, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    shots = {}
    with zipfile.ZipFile(archive) as zf:
        for name in zf.namelist():
            if name.startswith("screenshots/") and name.endswith(".png"):
                stem = pathlib.Path(name).stem
                image = Image.open(io.BytesIO(zf.read(name))).convert("RGB")
                image = image.resize((WIDTH, round(image.height * WIDTH / image.width)))
                image.save(out / f"{stem}.jpg", quality=70)
                shots[stem] = image
    screens = sorted({stem.split("-", 1)[1] for stem in shots if "-" in stem})
    for screen in screens:
        row = [shots[f"{v}-{screen}"] for v in VARIANTS if f"{v}-{screen}" in shots]
        sheet = Image.new("RGB", (sum(i.width for i in row) + 10 * (len(row) - 1), max(i.height for i in row)), "white")
        x = 0
        for image in row:
            sheet.paste(image, (x, 0))
            x += image.width + 10
        sheet.save(out / f"sheet-{screen}.jpg", quality=70)
    print(f"{len(shots)} screenshots, {len(screens)} sheets -> {out}")


if __name__ == "__main__":
    main()
