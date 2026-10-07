#!/usr/bin/env python3
"""
Build g9-battle-sprites-gen3's atlases: gen 4-9 species only (National Dex
#387-1025), packed from the DBK sprite sheets and the party icon atlas.

Inputs (defaults are the layouts of the two local checkouts):
  --sheets DIR   the DBK pack's per-species sheets: DIR/{front,front_shiny,
                 back,back_shiny}/<STEM>.png, one horizontal strip of frames
                 per sheet, frame height == sheet height
  --payload DIR  national_dex_gen3's data/species (id + dex per species)
  --dbk FILE     data/dbk_data.lua  (species id -> sheet stem)
  --icons FILE   data/icon_data.lua (species id -> icon name, icon name -> cell)
  --icon-atlas   assets/icons/party_icons.png (16x16 cells, 60 columns)

Outputs (under the mod root, --out):
  assets/atlas/battle_<variant>_<fs>.png     one uniform sheet per frame size; variant: front, front_shiny,
                                             back, back_shiny
  assets/atlas/party_icons_<page>.png        16x16 cells, two frames per icon
  data/atlas_index.lua                       species id -> atlas cells

Battle frames are brought down to the game's pixel grid (see art_pixel):
nearest-neighbour, one art pixel -> one game pixel. Icons are copied as-is.
Output is deterministic (sorted input, fixed shelf
packing, no PNG metadata), so a rebuild produces identical bytes.

Usage:
  python tools/build_atlas.py --sheets ../g9-battle-sprites/assets \
      --payload ../national_dex_gen3/data/species --dbk ../g9-battle-sprites/data/dbk_data.lua \
      --icons ../g9-battle-sprites/data/icon_data.lua \
      --icon-atlas ../g9-battle-sprites/assets/icons/party_icons.png
"""

from __future__ import annotations

import argparse
import glob
import os
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FIRST_DEX, LAST_DEX = 387, 1025
PAGE_SIZE = 4096          # max atlas edge; a page fills shelf by shelf, then a new page
VARIANTS = ["front", "front_shiny", "back", "back_shiny"]
ICON_CELL = 16
ICON_COLS = 60            # the source icon atlas's column count
ICON_FRAMES = 2


def read_species_ids(payload: Path) -> list[tuple[int, str]]:
    """(dex, id) for every payload record in FIRST_DEX..LAST_DEX, sorted."""
    recs = []
    for path in sorted(glob.glob(str(payload / "[0-9]*.lua"))):
        text = Path(path).read_text(encoding="utf-8")
        for block in re.split(r"\n  \{", text):
            i = re.search(r'\bid = "([^"]+)"', block)
            d = re.search(r"\bdex = (\d+)", block)
            if i and d and FIRST_DEX <= int(d.group(1)) <= LAST_DEX:
                recs.append((int(d.group(1)), i.group(1)))
    recs.sort()
    if len(recs) != LAST_DEX - FIRST_DEX + 1:
        raise SystemExit(f"payload has {len(recs)} species in #{FIRST_DEX}-{LAST_DEX}, expected "
                         f"{LAST_DEX - FIRST_DEX + 1}")
    return recs


def read_map(path: Path, name: str) -> dict[str, str]:
    """The `["KEY"] = "VALUE"` pairs of one table in a generated Lua data file."""
    text = path.read_text(encoding="utf-8")
    section = re.search(rf"{name}\s*=\s*\{{(.*?)\n  \}}", text, re.S)
    body = section.group(1) if section else text
    return dict(re.findall(r'\["([^"]+)"\]\s*=\s*"([^"]+)"', body))


def read_icon_base(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="utf-8")
    section = re.search(r"base\s*=\s*\{(.*?)\n  \}", text, re.S)
    return {k: int(v) for k, v in re.findall(r'\["([^"]+)"\]\s*=\s*(\d+)', section.group(1))}


class Shelf:
    """Row-major shelf packer over pages of PAGE_SIZE. Items are placed in the
    order given (callers sort), so the layout is reproducible."""

    def __init__(self):
        self.pages: list[dict] = []   # {"img": Image, "x": int, "y": int, "shelfH": int}

    def place(self, w: int, h: int) -> tuple[int, int, int]:
        if w > PAGE_SIZE or h > PAGE_SIZE:
            raise SystemExit(f"a {w}x{h} sheet is larger than one {PAGE_SIZE}px page")
        if not self.pages:
            self._new_page()
        page = self.pages[-1]
        if page["x"] + w > PAGE_SIZE:            # start a new shelf
            page["y"] += page["shelfH"]
            page["x"], page["shelfH"] = 0, 0
        if page["y"] + h > PAGE_SIZE:            # start a new page
            self._new_page()
            page = self.pages[-1]
        x, y = page["x"], page["y"]
        page["x"] += w
        page["shelfH"] = max(page["shelfH"], h)
        return len(self.pages) - 1, x, y

    def _new_page(self):
        self.pages.append({"img": Image.new("RGBA", (PAGE_SIZE, PAGE_SIZE), (0, 0, 0, 0)),
                           "x": 0, "y": 0, "shelfH": 0})


def save(pages: list[dict], prefix: str, out_dir: Path, used_w: dict[int, int],
         used_h: dict[int, int]) -> list[str]:
    names = []
    for i, page in enumerate(pages):
        w = used_w.get(i, 0)
        h = used_h.get(i, 0)
        if w == 0 or h == 0:
            continue
        name = f"{prefix}_{i}.png"
        page["img"].crop((0, 0, w, h)).save(out_dir / name, optimize=True, compress_level=9)
        names.append(name)
    return names


def art_pixel(img: Image.Image) -> int:
    """Pixels per art pixel in a sheet: the most common run of identical
    horizontal pixels (>= 2), or 1 when the art has no runs. The DBK art is
    drawn at about 2x the game's pixel grid, so this is 2 for most sheets."""
    from collections import Counter
    w, h = img.size
    px = img.load()
    runs: Counter[int] = Counter()
    for y in range(0, h, 2):
        run = 1
        for x in range(1, w):
            if px[x, y] == px[x - 1, y]:
                run += 1
            else:
                if run >= 2:
                    runs[run] += 1
                run = 1
    if not runs:
        return 1
    return max(1, min(4, runs.most_common(1)[0][0]))


def build_battle(sheets: Path, dbk: dict[str, str], species: list[tuple[int, str]],
                 out_dir: Path, index: dict[str, dict]) -> None:
    """Battle frames are grouped by their game-pixel frame size. Each group is
    one uniform sheet per variant: every cell is fs x fs, and a species' frames
    sit in consecutive cells. Frame n of a species is cell start + n, at
    ((start + n) % cols * fs, (start + n) // cols * fs)."""
    for variant in VARIANTS:
        folder = sheets / variant
        groups: dict[int, list[tuple[int, str, Image.Image, int, int]]] = {}
        for _dex, sid in species:
            stem = dbk.get(sid)
            if stem is None:
                continue
            path = folder / f"{stem}.png"
            if not path.exists():
                continue
            with Image.open(path) as im:
                img = im.convert("RGBA")
            w, h = img.size
            # true size: every frame keeps its source pixels (no art-pixel
            # reduction); the runtime shrinks only what does not fit the box
            g = 1
            fs = h
            frames = max(1, round(w / h))
            groups.setdefault(fs, []).append((_dex, sid, img, frames, g))

        written = 0
        for fs in sorted(groups):
            members = groups[fs]
            total = sum(m[3] for m in members)
            cols = max(1, min(total, PAGE_SIZE // fs))
            rows = -(-total // cols)
            sheet = Image.new("RGBA", (cols * fs, rows * fs), (0, 0, 0, 0))
            start = 0
            for _dex, sid, img, frames, g in members:
                h = img.height
                for n in range(frames):
                    cell = img.crop((n * h, 0, min((n + 1) * h, img.width), h))
                    frame = cell

                    k = start + n
                    sheet.paste(frame, ((k % cols) * fs, (k // cols) * fs))
                index.setdefault(sid, {})[variant] = {"sheet": fs, "start": start,
                                                      "fs": fs, "cols": cols, "frames": frames}
                start += frames
            name = f"battle_{variant}_{fs}.png"
            sheet.save(out_dir / name, optimize=True, compress_level=9)
            written += 1
        print(f"  {variant}: {len(groups)} size groups, {written} sheets")


def build_icons(icon_atlas: Image.Image, icon_base: dict[str, int], icons: dict[str, str],
                species: list[tuple[int, str]], out_dir: Path, index: dict[str, dict]) -> None:
    shelf = Shelf()
    used_w: dict[int, int] = {}
    used_h: dict[int, int] = {}
    cell_w = ICON_CELL * ICON_FRAMES
    picked = []
    for _dex, sid in species:
        name = icons.get(sid)
        if name is None or name not in icon_base:
            continue
        picked.append((sid, icon_base[name]))
    # ordering by source cell keeps the output stable across rebuilds
    for sid, cell in sorted(picked, key=lambda p: (p[1], p[0])):
        col, row = cell % ICON_COLS, cell // ICON_COLS
        x0, y0 = col * ICON_CELL, row * ICON_CELL
        strip = icon_atlas.crop((x0, y0, x0 + cell_w, y0 + ICON_CELL))
        page, x, y = shelf.place(cell_w, ICON_CELL)
        shelf.pages[page]["img"].paste(strip, (x, y))
        used_w[page] = max(used_w.get(page, 0), x + cell_w)
        used_h[page] = max(used_h.get(page, 0), y + ICON_CELL)
        index.setdefault(sid, {})["icon"] = {"page": page, "x": x, "y": y,
                                             "cell": ICON_CELL, "frames": ICON_FRAMES}
    names = save(shelf.pages, "party_icons", out_dir, used_w, used_h)
    print(f"  party icons: {len(picked)} icons on {len(names)} page(s)")


def write_index(index: dict[str, dict], path: Path, species: list[tuple[int, str]]) -> None:
    lines = [
        "-- Generated by tools/build_atlas.py. Do not edit by hand; rerun the tool instead.",
        "-- species id -> where each of its sprites sits in assets/atlas/.",
        "-- battle_<variant>_<fs>.png: uniform fs x fs cells, `cols` per row; frame n",
        "-- of a species is cell start + n.",
        "-- party_icons_<page>.png: `frames` 16x16 cells side by side from x, y.",
        "return {",
        "  species = {",
    ]
    for dex, sid in species:
        entry = index.get(sid)
        if not entry:
            continue
        parts = []
        for key in ["front", "front_shiny", "back", "back_shiny"]:
            if key in entry:
                c = entry[key]
                parts.append(f'{key} = {{ sheet = {c["sheet"]}, start = {c["start"]}, '
                             f'fs = {c["fs"]}, cols = {c["cols"]}, frames = {c["frames"]} }}')
        if "icon" in entry:
            c = entry["icon"]
            parts.append(f'icon = {{ page = {c["page"]}, x = {c["x"]}, y = {c["y"]}, '
                         f'cell = {c["cell"]}, frames = {c["frames"]} }}')
        lines.append(f'    ["{sid}"] = {{ dex = {dex}, ' + ", ".join(parts) + " },")
    lines += ["  },", "}", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheets", type=Path, default=ROOT.parent / "g9-battle-sprites" / "assets")
    ap.add_argument("--payload", type=Path, default=ROOT.parent / "national_dex_gen3" / "data" / "species")
    ap.add_argument("--dbk", type=Path, default=ROOT.parent / "g9-battle-sprites" / "data" / "dbk_data.lua")
    ap.add_argument("--icons", type=Path, default=ROOT.parent / "g9-battle-sprites" / "data" / "icon_data.lua")
    ap.add_argument("--icon-atlas", type=Path,
                    default=ROOT.parent / "g9-battle-sprites" / "assets" / "icons" / "party_icons.png")
    ap.add_argument("--out", type=Path, default=ROOT)
    args = ap.parse_args()

    species = read_species_ids(args.payload)
    dbk = read_map(args.dbk, "species")
    icons = read_map(args.icons, "species")
    icon_base = read_icon_base(args.icons)
    out_atlas = args.out / "assets" / "atlas"
    out_atlas.mkdir(parents=True, exist_ok=True)
    for old in out_atlas.glob("*.png"):          # a rebuild replaces the whole set
        old.unlink()
    (args.out / "data").mkdir(parents=True, exist_ok=True)

    index: dict[str, dict] = {}
    print(f"species #{FIRST_DEX}-{LAST_DEX}: {len(species)}")
    build_battle(args.sheets, dbk, species, out_atlas, index)
    with Image.open(args.icon_atlas) as icon_atlas:
        build_icons(icon_atlas.convert("RGBA"), icon_base, icons, species, out_atlas, index)
    write_index(index, args.out / "data" / "atlas_index.lua", species)
    print("wrote", args.out / "data" / "atlas_index.lua")


if __name__ == "__main__":
    main()
