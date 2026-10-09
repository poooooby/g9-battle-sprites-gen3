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
  --icons-dir DIR  the pack's Icons folder: one PNG per icon, two frames side by side

Outputs (under the mod root, --out):
  assets/atlas/battle_<variant>_<n>.png      pages of at most 4096x4096 holding blocks of
                                             uniform cells; variant: front, front_shiny,
                                             back, back_shiny
  assets/atlas/party_icons_<page>.png        32x32 cells, two frames per icon
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
import json
import os
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FIRST_DEX, LAST_DEX = 387, 1025
SLOT_OFFSET = 64        # slot = dex + 64, as national_dex_gen3 registers the base species
PAGE_SIZE = 4096          # max atlas edge; a page fills shelf by shelf, then a new page
VARIANTS = ["front", "front_shiny", "back", "back_shiny"]
BLOCK_MAX = 2048          # tallest block, so blocks pack tightly into pages
BACK_VARIANTS = ("back", "back_shiny")

# Sheets of the DBK pack that the pack's own species map (dbk_data.lua) names wrongly or not
# at all, by their id in national_dex_gen3: Flabebe, Floette and Florges keep their colours in
# _1.._4 (yellow, orange, blue, white; the base is red), Eternal Floette is _6 (_5 is the
# Mega), the east-sea Shellos and Gastrodon are _1, Galarian Darmanitan (Standard) is _2 (the
# pack's _1 is Zen Mode, which dbk_data.lua maps all three Darmanitan forms to), and Alcremie's
# nine creams are blocks of seven sheets, one per sweet (ALCREMIE, then _1.._62): each cream
# uses the first sheet of its block, the Strawberry Sweet. Checked by eye against the sheets.
STEM_OVERRIDES = {
    "FLOETTE_ETERNAL": "FLOETTE_6",
    "DARMANITAN_GALAR_STANDARD": "DARMANITAN_2",
    "SHELLOS_EAST": "SHELLOS_1", "GASTRODON_EAST": "GASTRODON_1",
    **{f"ALCREMIE_{cream}": f"ALCREMIE_{7 * k}"
       for k, cream in enumerate(("RUBY_CREAM", "MATCHA_CREAM", "MINT_CREAM", "LEMON_CREAM",
                                  "SALTED_CREAM", "RUBY_SWIRL", "CARAMEL_SWIRL", "RAINBOW_SWIRL"), 1)},
    **{f"{base}_{color}": f"{base}_{n}"
       for base in ("FLABEBE", "FLOETTE", "FLORGES")
       for n, color in enumerate(("YELLOW", "ORANGE", "BLUE", "WHITE"), 1)},
}

# Party icons live in their own folder (the Gen 9 Pack's Icons/), numbered like the sheets for
# most species but not all, and one file is spelt in lower case. A form's icon is its sheet's
# stem unless listed here: Basculin's icons run red, blue, white (_1 = blue, _2 = white-striped;
# the sheets run base = white-striped, _2 = red, _3 = blue).
ICON_STEMS = {
    "BASCULIN_WHITE_STRIPED": "BASCULIN_2",
    "BASCULEGION_FEMALE": "BASCULEGION_female",
}

# Pokemon whose female looks different but is the same species here (national_dex_gen3 keeps
# their stats): female id -> species id. Their sheets are packed under the female id and the
# runtime picks them by the Pokemon's gender.
FEMALE_SHEETS = {"MEOWSTIC_FEMALE": "MEOWSTIC", "OINKOLOGNE_FEMALE": "OINKOLOGNE"}
ICON_CELL = 32            # the engine's own menu icon size
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


# Gen 1-3 (#1-386) are not in national_dex_gen3's payload: they are the game's own species.
# Their names and the National Dex number of each internal species id come from the engine's
# extracted pokemon data (names.lua, national.lua), and their atlas slot is the internal id.
# Unown (#201) is left out: the engine draws its 28 letter forms as separate species and the
# pack has a single UNOWN sheet, so animating it would turn every letter into the same one.
GEN3_LAST_DEX = 386
GEN3_SKIP = {201}


def gen3_id(name: str) -> str:
    """The pack's id for an engine species name (NIDORAN♀ -> NIDORAN_F, MR. MIME -> MR_MIME)."""
    n = name.upper().replace("♀", "_F").replace("♂", "_M")
    n = re.sub(r"[.']", "", n)
    return re.sub(r"[\s\-]+", "_", n)


def read_gen3_species(data: Path) -> list[tuple[int, str, int]]:
    """(dex, id, internal slot) for National Dex #1-386, sorted by dex."""
    names = dict(re.findall(r'\[(\d+)\] = "([^"]*)"', (data / "names.lua").read_text(encoding="utf-8")))
    national = dict(re.findall(r"toNational\[(\d+)\] = (\d+)", (data / "national.lua").read_text(encoding="utf-8")))
    rows = []
    for slot, dex in national.items():
        slot, dex = int(slot), int(dex)
        if 1 <= dex <= GEN3_LAST_DEX and dex not in GEN3_SKIP and names.get(str(slot)):
            rows.append((dex, gen3_id(names[str(slot)]), slot))
    rows.sort()
    if len({d for d, _i, _s in rows}) != GEN3_LAST_DEX - len(GEN3_SKIP):
        raise SystemExit(f"{data} lists {len(rows)} species in #1-{GEN3_LAST_DEX}, expected "
                         f"{GEN3_LAST_DEX - len(GEN3_SKIP)}")
    return rows


def read_forms(payload: Path) -> list[tuple[int, str, int, str]]:
    """(base dex, id, slot, base id) for each alternate form in national_dex_gen3's
    data/species/forms.lua (WORMADAM_SANDY, DARUMAKA_GALAR, ...), in slot order.
    A form is a species of its own in the engine but reports its base's dex."""
    path = payload / "forms.lua"
    if not path.exists():
        return []
    rows = []
    for block in re.split(r"\n  \{", path.read_text(encoding="utf-8")):
        i = re.search(r'id = "([^"]+)"', block)
        sl = re.search(r"slot = (\d+)", block)
        d = re.search(r"baseDex = (\d+)", block)
        b = re.search(r'baseSpecies = "([^"]+)"', block)
        if i and sl and d and b:
            rows.append((int(d.group(1)), i.group(1), int(sl.group(1)), b.group(1)))
    return sorted(rows, key=lambda r: r[2])


def read_map(path: Path, name: str) -> dict[str, str]:
    """The `["KEY"] = "VALUE"` pairs of one table in a generated Lua data file."""
    text = path.read_text(encoding="utf-8")
    section = re.search(rf"{name}\s*=\s*\{{(.*?)\n  \}}", text, re.S)
    body = section.group(1) if section else text
    return dict(re.findall(r'\["([^"]+)"\]\s*=\s*"([^"]+)"', body))


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


def creature_box(boxes: list[tuple[int, int, int, int]]) -> tuple[int, int, int, int] | None:
    """Where the creature sits in its frame, from its per-frame bounding boxes: the
    left / top edge are taken a little inside the extremes and the right / bottom
    from the middle, so a few exaggerated frames (a head flung upward, a wing
    flare) do not pull the anchor away from the pose it holds most of the time.
    A union over every frame did exactly that: Blacephalon's head swings 85 px, so
    anchoring its union box left the body below the box bottom in most frames."""
    if not boxes:
        return None

    def pct(values: list[int], p: float) -> int:
        ordered = sorted(values)
        return ordered[min(len(ordered) - 1, int(p * len(ordered)))]

    x0 = pct([b[0] for b in boxes], 0.25)
    y0 = pct([b[1] for b in boxes], 0.25)
    x1 = pct([b[2] for b in boxes], 0.75)
    y1 = pct([b[3] for b in boxes], 0.5)
    return (x0, y0, max(x1, x0 + 1), max(y1, y0 + 1))


# Front pics drawn lower than the frame's bottom edge puts them, in px, by species id: a tall front
# frame whose creature floats high (Noivern's) would otherwise stand above the top of the screen.
# Written to the front cells as `fy`.
FRONT_DROP = {"NOIVERN": 20}


BACK_SCALES = (1.0, 1.5, 2.0)   # the clean steps a back sprite may be upscaled by (2 px art pixels -> 2/3/4 px)


def back_scale(visible: int, height: int) -> float:
    """The scale a back sprite is drawn at: the reference's visible height over our body's
    first-frame height, snapped to the nearest clean step and never below 1 (no downsizing).
    Pure; shared with tools/back_framing.py."""
    if height <= 0 or visible <= 0:
        return 1.0
    exact = visible / height
    return min(BACK_SCALES, key=lambda s: (abs(s - exact), s))


def trim_window(trims: dict, sid: str, variant: str, frames: int) -> tuple[int, int] | None:
    """(start, count) of the frames to keep for `sid`, from tools/trim_loops.py, or None.
    A shiny sheet uses its normal sheet's window; one that no longer matches is ignored."""
    side = "back" if variant in BACK_VARIANTS else "front"
    win = trims.get(sid, {}).get(side)
    if not win:
        return None
    start, count = int(win[0]), int(win[1])
    return (start, count) if 0 <= start and count >= 1 and start + count <= frames else None


def build_battle(sheets: Path, dbk: dict[str, str], species: list[tuple[int, str]],
                 out_dir: Path, index: dict[str, dict], trims: dict | None = None,
                 framing: dict | None = None) -> None:
    """Battle frames are grouped by their game-pixel frame size. A group is cut
    into blocks of uniform fs x fs cells (a species' frames stay together in
    one block), and the blocks of every size are shelf-packed onto shared pages
    of at most PAGE_SIZE x PAGE_SIZE, per variant. A cell records its block's
    origin: frame n of a species is cell start + n, at
    (ox + (start + n) % cols * fs, oy + (start + n) // cols * fs) on page `sheet`."""
    for variant in VARIANTS:
        folder = sheets / variant
        groups: dict[int, list[tuple[int, str, Image.Image, int]]] = {}
        for _dex, sid in species:
            stem = dbk.get(sid)
            if stem is None:
                continue
            path = folder / f"{stem}.png"
            if not path.exists():
                continue
            with Image.open(path) as im:
                img = im.convert("RGBA")
            # true size: every frame keeps its source pixels; the runtime
            # shrinks only what does not fit the box
            fs = img.height
            frames = max(1, round(img.width / fs))
            win = trim_window(trims or {}, sid, variant, frames)
            if win:
                # a long animation trimmed to a window that loops (tools/trim_loops.py)
                img = img.crop((win[0] * fs, 0, (win[0] + win[1]) * fs, fs))
                frames = win[1]
            groups.setdefault(fs, []).append((_dex, sid, img, frames))

        # cut each size group into blocks
        blocks = []   # (fs, cols, rows, members)
        for fs in sorted(groups):
            cols = max(1, PAGE_SIZE // fs)
            capacity = cols * max(1, BLOCK_MAX // fs)
            cur: list[tuple] = []
            used = 0
            for m in groups[fs]:
                if m[3] > capacity:
                    raise SystemExit(f"{m[1]} has {m[3]} frames, more than one {fs}px block holds")
                if used + m[3] > capacity:
                    blocks.append((fs, cols, cur))
                    cur, used = [], 0
                cur.append(m)
                used += m[3]
            if cur:
                blocks.append((fs, cols, cur))

        def dims(blk):
            fs, cols, members = blk
            total = sum(m[3] for m in members)
            c = min(cols, total)
            return fs, c, -(-total // c)

        # tallest first keeps the shelves tight; ties break on fs so it is stable
        blocks.sort(key=lambda blk: (-dims(blk)[0] * dims(blk)[2], dims(blk)[0], dims(blk)[1]))
        shelf = Shelf()
        used_w: dict[int, int] = {}
        used_h: dict[int, int] = {}
        for blk in blocks:
            fs, pcols, rows = dims(blk)
            w, h = pcols * fs, rows * fs
            page, ox, oy = shelf.place(w, h)
            used_w[page] = max(used_w.get(page, 0), ox + w)
            used_h[page] = max(used_h.get(page, 0), oy + h)
            canvas = shelf.pages[page]["img"]
            start = 0
            for _dex, sid, img, frames in blk[2]:
                boxes = []
                for n in range(frames):
                    frame = img.crop((n * fs, 0, min((n + 1) * fs, img.width), fs))
                    k = start + n
                    canvas.paste(frame, (ox + (k % pcols) * fs, oy + (k // pcols) * fs))
                    bb = frame.getbbox()
                    if bb:
                        boxes.append(bb)
                # the body is the FIRST frame's box: a head or wing flung out later in the
                # animation is not what the creature is anchored on (Blacephalon's head)
                first = img.crop((0, 0, fs, fs)).getbbox()
                box = first or creature_box(boxes)
                extent = (min(b[0] for b in boxes), min(b[1] for b in boxes),
                          max(b[2] for b in boxes), max(b[3] for b in boxes)) if boxes else None
                cell = {"sheet": page, "start": start, "fs": fs, "cols": pcols, "frames": frames,
                        "ox": ox, "oy": oy}
                if variant in BACK_VARIANTS and box:
                    # where the creature sits inside its frame (see creature_box), so the
                    # runtime can anchor on it rather than on the frame's empty margins
                    cell.update({"cx0": box[0], "cy0": box[1], "cx1": box[2], "cy1": box[3],
                                 "ux0": extent[0], "uy0": extent[1], "ux1": extent[2], "uy1": extent[3]})
                    ref = (framing or {}).get(sid)
                    if ref:
                        # the cart's own framing of this species (tools/back_framing.py): the row its
                        # body's top sits on and the scale that brings our body to its on-screen height
                        cell["bt"] = int(ref["t"])
                        cell["bx"] = float(ref.get("x", 32))      # the reference body's centre column
                        cell["bv"] = int(ref["v"])      # the reference body's height: the exact zoom with gen3-hd-sprites
                        cell["bs"] = back_scale(int(ref["v"]), box[3] - box[1])
                if variant not in BACK_VARIANTS and sid in FRONT_DROP:
                    cell["fy"] = FRONT_DROP[sid]
                index.setdefault(sid, {})[variant] = cell
                start += frames
        names = save(shelf.pages, f"battle_{variant}", out_dir, used_w, used_h)
        print(f"  {variant}: {len(groups)} size groups, {len(blocks)} blocks, {len(names)} pages")


def norm(name: str) -> str:
    """Icon file stems drop the underscores of species ids (MIME_JR -> MIMEJR);
    form suffixes keep theirs (ABSOL_1), so only a species id is normalised by
    its callers, never a stem."""
    return name.replace("_", "")


def icon_phase(px: object, size: int, axis: int) -> int:
    """Which of the two grid alignments (0 or 1) the 2x pixel art of one icon frame
    sits on, along `axis`: the offset at which the fewest neighbouring pixel pairs
    differ across what should be one art pixel. Most of the pack starts its art
    pixels at an even offset; some frames are drawn one pixel over."""
    best, best_bad = 0, None
    for phase in (0, 1):
        bad = 0
        for a in range(phase, size - 1, 2):
            for b in range(size):
                p, q = ((a, b), (a + 1, b)) if axis == 0 else ((b, a), (b, a + 1))
                if px[p] != px[q]:
                    bad += 1
        if best_bad is None or bad < best_bad:
            best, best_bad = phase, bad
    return best


def reduce_icon(frame: Image.Image) -> Image.Image:
    """One icon frame down to ICON_CELL x ICON_CELL, without blending. The art is
    2x pixel art, so each art pixel is read once from the grid it was drawn on:
    averaging 2x2 blocks across an off-grid frame smears every edge into new
    colours. A frame that is not twice the cell (a few 80px ones) is point-sampled."""
    if frame.size != (ICON_CELL * 2, ICON_CELL * 2):
        return frame.resize((ICON_CELL, ICON_CELL), Image.NEAREST)
    px = frame.load()
    ox, oy = icon_phase(px, frame.width, 0), icon_phase(px, frame.height, 1)
    out = Image.new("RGBA", (ICON_CELL, ICON_CELL))
    dst = out.load()
    for y in range(ICON_CELL):
        for x in range(ICON_CELL):
            dst[x, y] = px[2 * x + ox, 2 * y + oy]
    return out


def build_icons(icon_dir: Path, species: list[tuple[int, str]], out_dir: Path,
                index: dict[str, dict], dbk: dict[str, str] | None = None,
                form_ids: set[str] | None = None) -> None:
    """Packs the base icon of each species (two animation frames side by side in
    the source, each as wide as it is tall) as ICON_CELL x ICON_CELL frames. Forms
    and variants are not packed. Pages stay within PAGE_SIZE."""
    stems = {path.stem: path for path in icon_dir.glob("*.png")}
    by_norm = {norm(k): v for k, v in stems.items() if not re.search(r"_(\d+|female)$", k)}
    shelf = Shelf()
    used_w: dict[int, int] = {}
    used_h: dict[int, int] = {}
    cell_w = ICON_CELL * ICON_FRAMES
    missing = []
    for _dex, sid in species:
        path = stems.get(sid) or by_norm.get(norm(sid))
        if sid in ICON_STEMS:
            path = stems.get(ICON_STEMS[sid])
        elif path is None and dbk and form_ids and sid in form_ids:
            path = stems.get(dbk.get(sid, ""))      # a form's icon is named by its sprite stem
        if path is None:
            missing.append(sid)
            continue
        with Image.open(path) as im:
            img = im.convert("RGBA")
        fw = img.width // ICON_FRAMES
        strip = Image.new("RGBA", (cell_w, ICON_CELL), (0, 0, 0, 0))
        for f in range(ICON_FRAMES):
            frame = img.crop((f * fw, 0, (f + 1) * fw, img.height))
            strip.paste(reduce_icon(frame), (f * ICON_CELL, 0))
        page, x, y = shelf.place(cell_w, ICON_CELL)
        shelf.pages[page]["img"].paste(strip, (x, y))
        used_w[page] = max(used_w.get(page, 0), x + cell_w)
        used_h[page] = max(used_h.get(page, 0), y + ICON_CELL)
        index.setdefault(sid, {})["icon"] = {"page": page, "x": x, "y": y, "cell": ICON_CELL,
                                             "frames": ICON_FRAMES}
    names = save(shelf.pages, "party_icons", out_dir, used_w, used_h)
    print(f"  party icons: {len(species) - len(missing)}/{len(species)} species on "
          f"{len(names)} page(s)")
    if missing:
        print("  no icon for:", ", ".join(missing))


def write_index(index: dict[str, dict], path: Path, species: list[tuple[int, str]],
                slots: dict[str, int]) -> None:
    lines = [
        "-- Generated by tools/build_atlas.py. Do not edit by hand; rerun the tool instead.",
        "-- species id -> where each of its sprites sits in assets/atlas/.",
        "-- battle_<variant>_<n>.png: blocks of uniform fs x fs cells at (ox, oy), `cols` per",
        "-- row; frame n of a species is cell start + n. Back cells also carry cx0, cy0, cx1,",
        "-- cy1: the creature's typical box inside its frame (what it is anchored on); ux0, uy0,",
        "-- ux1, uy1: the union of its box over the whole animation (how much room it needs).",
        "-- party_icons_<page>.png: `frames` 32x32 cells side by side from x, y.",
        "-- slot: the engine species slot the entry answers for. A form (WORMADAM_SANDY) has a",
        "-- slot of its own and its base species' dex; it reuses its base's cells where the",
        "-- pack has no sheet or icon of its own.",
        "-- female_of: instead of a slot, on the female sheets of Meowstic and Oinkologne: the slot",
        "-- of the species they belong to, shown when the Pokemon is female.",
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
                text = (f'{key} = {{ sheet = {c["sheet"]}, start = {c["start"]}, '
                        f'fs = {c["fs"]}, cols = {c["cols"]}, frames = {c["frames"]}, '
                        f'ox = {c["ox"]}, oy = {c["oy"]}')
                if "cx0" in c:
                    text += f', cx0 = {c["cx0"]}, cy0 = {c["cy0"]}, cx1 = {c["cx1"]}, cy1 = {c["cy1"]}'
                    text += f', ux0 = {c["ux0"]}, uy0 = {c["uy0"]}, ux1 = {c["ux1"]}, uy1 = {c["uy1"]}'
                if "fy" in c:
                    text += f', fy = {c["fy"]}'
                if "bt" in c:
                    text += f', bt = {c["bt"]}, bs = {c["bs"]:g}, bv = {c["bv"]}, bx = {c["bx"]:g}'
                parts.append(text + " }")
        if "icon" in entry:
            c = entry["icon"]
            parts.append(f'icon = {{ page = {c["page"]}, x = {c["x"]}, y = {c["y"]}, '
                         f'cell = {c["cell"]}, frames = {c["frames"]} }}')
        if sid in FEMALE_SHEETS:
            # not a species of its own: the runtime reaches it from the species' slot
            owner = f'female_of = {slots[FEMALE_SHEETS[sid]]}'
        else:
            owner = f'slot = {slots[sid]}'
        lines.append(f'    ["{sid}"] = {{ dex = {dex}, {owner}, ' + ", ".join(parts) + " },")
    lines += ["  },", "}", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def add_source_args(ap: argparse.ArgumentParser) -> None:
    """The input locations shared by the build and the tools that read the same sheets."""
    ap.add_argument("--sheets", type=Path, default=ROOT.parent / "g9-battle-sprites" / "assets")
    ap.add_argument("--payload", type=Path, default=ROOT.parent / "national_dex_gen3" / "data" / "species")
    ap.add_argument("--gen3-data", type=Path, default=ROOT.parent / "gen1recomp" / "firered" / "data"
                    / "generated" / "gba" / "pokemon", help="the engine's extracted pokemon data "
                    "(names.lua, national.lua): where Gen 1-3's names and slots come from")
    ap.add_argument("--dbk", type=Path, default=ROOT.parent / "g9-battle-sprites" / "data" / "dbk_data.lua")


def battle_species(args) -> tuple[dict[str, str], list[tuple[int, str]]]:
    """(id -> sheet stem, [(dex, id)]) for every species the build draws in battle: Gen 1-3,
    #387-1025, the alternate forms and the female sheets. Shared with tools/trim_loops.py and
    tools/back_framing.py so they see exactly the sheets the build packs."""
    species = read_species_ids(args.payload)
    forms = read_forms(args.payload)
    gen3 = read_gen3_species(args.gen3_data)
    dbk = read_map(args.dbk, "species")
    dbk.update(STEM_OVERRIDES)
    classic = [(dex, sid) for dex, sid, _slot in gen3]
    species = species + [(dex, fid) for dex, fid, _slot, _base in forms]
    dex_of = {sid: dex for dex, sid in species}
    females = [(dex_of[base], fid) for fid, base in FEMALE_SHEETS.items() if base in dex_of]
    return dbk, classic + species + females


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--icons-dir", type=Path, default=ROOT.parent / "1SpriteReferences" / "Gen 9 Pack"
                    / "Graphics" / "Pokemon" / "Icons")
    ap.add_argument("--trims", type=Path, default=ROOT / "tools" / "loop_trims.json",
                    help="which frames of each long animation to keep (tools/trim_loops.py)")
    ap.add_argument("--framing", type=Path, default=ROOT / "tools" / "back_framing.json",
                    help="each back sprite's cart reference (tools/back_framing.py)")
    ap.add_argument("--out", type=Path, default=ROOT)
    args = ap.parse_args()
    trims = json.loads(args.trims.read_text(encoding="utf-8")) if args.trims.exists() else {}
    framing = json.loads(args.framing.read_text(encoding="utf-8")) if args.framing.exists() else {}

    species = read_species_ids(args.payload)
    forms = read_forms(args.payload)
    gen3 = read_gen3_species(args.gen3_data)
    slots = {sid: dex + SLOT_OFFSET for dex, sid in species}
    slots.update({sid: slot for _dex, sid, slot in gen3})
    slots.update({fid: slot for _dex, fid, slot, _base in forms})
    form_ids = {fid for _dex, fid, _slot, _base in forms}
    dbk = read_map(args.dbk, "species")
    dbk.update(STEM_OVERRIDES)
    base_species = list(species)
    species = species + [(dex, fid) for dex, fid, _slot, _base in forms]
    classic = [(dex, sid) for dex, sid, _slot in gen3]
    no_sheet = [sid for _dex, sid in classic if sid not in dbk]
    if no_sheet:
        print("  Gen 1-3 species with no sheet in the pack:", ", ".join(no_sheet))
    out_atlas = args.out / "assets" / "atlas"
    out_atlas.mkdir(parents=True, exist_ok=True)
    for old in out_atlas.glob("*.png"):          # a rebuild replaces the whole set
        old.unlink()
    (args.out / "data").mkdir(parents=True, exist_ok=True)

    index: dict[str, dict] = {}
    print(f"species #{FIRST_DEX}-{LAST_DEX}: {len(base_species)} + {len(forms)} forms; "
          f"Gen 1-3: {len(classic)}")
    dex_of = {sid: dex for dex, sid in species}
    females = [(dex_of[base], fid) for fid, base in FEMALE_SHEETS.items() if base in dex_of]
    build_battle(args.sheets, dbk, classic + species + females, out_atlas, index, trims, framing)
    build_icons(args.icons_dir, species, out_atlas, index, dbk, form_ids)
    # a form with no sheet or icon of its own in the pack reuses its base's
    reused = 0
    for _dex, fid, _slot, base in forms:
        for key in ("front", "front_shiny", "back", "back_shiny", "icon"):
            if key not in index.get(fid, {}) and key in index.get(base, {}):
                index.setdefault(fid, {})[key] = index[base][key]
                reused += 1
    if reused:
        print(f"  {reused} form sprite(s) reuse their base species' art")
    write_index(index, args.out / "data" / "atlas_index.lua", classic + species + females, slots)
    print("wrote", args.out / "data" / "atlas_index.lua")


if __name__ == "__main__":
    main()
