#!/usr/bin/env python3
"""
Fits our animated back sprites of the Gen 1-3 species to the cart's own static back sprites:
the same size, the same place in the 64x64 pic box, so an animated Pokemon sits over the
shoulder the way the game's does instead of further away.

For each species the first frame of the (trimmed) animation, cut to its body's bounding box, is
scaled and moved over the cart's back sprite (pokeemerald-expansion's back_gba.png, the cart's
own picture) until their silhouettes overlap best (intersection over union of the two
alpha masks, both clipped to the 64x64 box the engine draws). The search is over the scale
(around the size that makes the bounding boxes match) and a few pixels of position.

  python tools/back_fit.py report
  python tools/back_fit.py write              # tools/back_fit.json
  python tools/back_fit.py report --only TYRANITAR POOCHYENA

back_fit.json holds, per species: s (the scale), t (the row our body's top lands on), x (the column
of our body's centre) and iou (how well it fit). tools/build_atlas.py writes them into the back cells as
bz / bt / bx, replacing the height-only framing of tools/back_framing.py for these species.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_atlas as ba  # noqa: E402

ROOT = ba.ROOT
BOX = 64
MIN_IOU = 0.55      # below this the silhouettes are not trusted; the bounding boxes are matched
SCALE_MIN, SCALE_MAX = 0.9, 2.0


def cart_mask(path: Path) -> list[int]:
    """The cart sprite's silhouette as 64 row bitmasks (bit x set = content at column x)."""
    with Image.open(path) as im:
        if im.mode == "P":
            px = im.load()
            test = lambda x, y: px[x, y] != 0  # noqa: E731
        else:
            rgba = im.convert("RGBA")
            px = rgba.load()
            test = lambda x, y: px[x, y][3] > 0  # noqa: E731
        rows = []
        for y in range(BOX):
            m = 0
            for x in range(BOX):
                if test(x, y):
                    m |= 1 << x
            rows.append(m)
    return rows


def first_frame(sheet: Path, window) -> Image.Image | None:
    with Image.open(sheet) as im:
        fs = im.height
        start = window[0] if window else 0
        frame = im.convert("RGBA").crop((start * fs, 0, (start + 1) * fs, fs))
    box = frame.getbbox()
    return None if box is None else frame.crop(box)


def alpha_mask(img: Image.Image) -> Image.Image:
    return img.getchannel("A").point(lambda a: 255 if a > 0 else 0)


def placed_rows(mask_img: Image.Image, s: float, left: int, top: int) -> list[int]:
    """Our body mask scaled by s (nearest), its top-left at (left, top) in the box, as row bitmasks."""
    w, h = mask_img.size
    sw, sh = max(1, round(w * s)), max(1, round(h * s))
    scaled = mask_img.resize((sw, sh), Image.NEAREST)
    px = scaled.load()
    rows = [0] * BOX
    for y in range(sh):
        by = top + y
        if not 0 <= by < BOX:
            continue
        m = 0
        for x in range(sw):
            bx = left + x
            if 0 <= bx < BOX and px[x, y]:
                m |= 1 << bx
        rows[by] = m
    return rows


def iou(a: list[int], b: list[int]) -> float:
    inter = union = 0
    for x, y in zip(a, b):
        inter += (x & y).bit_count()
        union += (x | y).bit_count()
    return inter / union if union else 0.0


def fit(cart: list[int], body: Image.Image):
    """(iou, scale, left, top) of the best placement of our body mask over the cart's."""
    mask = alpha_mask(body)
    w, h = mask.size
    ys = [y for y, m in enumerate(cart) if m]
    xs = [x for m in cart for x in range(BOX) if m >> x & 1]
    cw, ch = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
    cx, cy0 = (max(xs) + min(xs) + 1) / 2, min(ys)
    s0 = (cw / w + ch / h) / 2
    best = (-1.0, s0, 0, 0)
    steps = [s0 * (0.72 + 0.02 * i) for i in range(0, 29)]
    for s in steps:
        sw, sh = w * s, h * s
        left0, top0 = round(cx - sw / 2), cy0
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                score = iou(cart, placed_rows(mask, s, left0 + dx, top0 + dy))
                if score > best[0]:
                    best = (score, s, left0 + dx, top0 + dy)
    if best[0] < MIN_IOU:
        # the poses differ too much for the silhouettes to agree: match the boxes instead
        s = min(max(s0, SCALE_MIN), SCALE_MAX)
        best = (best[0], s, round(cx - w * s / 2), cy0)
    best = (best[0], min(max(best[1], SCALE_MIN), SCALE_MAX), best[2], min(max(best[3], 0), BOX - 1))
    return best, (w, h)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=("report", "write"))
    ba.add_source_args(ap)
    ap.add_argument("--ref", type=Path, default=ROOT.parent / "pokeemerald-expansion" / "graphics" / "pokemon")
    ap.add_argument("--trims", type=Path, default=ROOT / "tools" / "loop_trims.json")
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--out", type=Path, default=ROOT / "tools" / "back_fit.json")
    args = ap.parse_args()

    trims = json.loads(args.trims.read_text(encoding="utf-8")) if args.trims.exists() else {}
    dbk, species = ba.battle_species(args)
    classic = {sid for dex, sid in species if dex <= ba.GEN3_LAST_DEX and "_" not in sid.replace("NIDORAN_", "").replace("HO_OH", "").replace("MR_MIME", "")} \
        | {"NIDORAN_F", "NIDORAN_M", "HO_OH", "MR_MIME"}
    table, rows = {}, []
    for dex, sid in species:
        if sid not in classic or (args.only and sid not in args.only):
            continue
        stem = dbk.get(sid)
        ref = args.ref / sid.lower() / "back_gba.png"
        sheet = args.sheets / "back" / f"{stem}.png" if stem else None
        if not (sheet and sheet.exists() and ref.exists()):
            continue
        body = first_frame(sheet, trims.get(sid, {}).get("back"))
        cart = cart_mask(ref)
        if body is None or not any(cart):
            continue
        (score, s, left, top), (w, h) = fit(cart, body)
        table[sid] = {"s": round(s, 4), "t": top, "x": round(left + w * s / 2, 2), "iou": round(score, 3)}
        rows.append((sid, s, top, left + w * s / 2, score, h * s))

    print(f"{len(rows)} Gen 1-3 species fitted to the cart's back sprites")
    if rows:
        ious = sorted(r[4] for r in rows)
        print(f"overlap (IoU): median {statistics.median(ious):.2f}, worst {ious[0]:.2f}, "
              f"p10 {ious[len(ious) // 10]:.2f}; scale median {statistics.median(r[1] for r in rows):.2f}x "
              f"(min {min(r[1] for r in rows):.2f}, max {max(r[1] for r in rows):.2f})")
        print("\n  species                  scale  top row  centre col  IoU   body px tall")
        spot = ("TYRANITAR", "POOCHYENA", "CLAMPERL", "TREECKO", "PIKACHU", "HORSEA", "SNORLAX", "WAILORD")
        show = [r for r in rows if args.only or r[0] in spot]
        show += sorted(rows, key=lambda r: r[4])[:6] if not args.only else []
        for r in show:
            print(f"  {r[0]:<22} {r[1]:>6.2f} {r[2]:>8} {r[3]:>11.1f} {r[4]:>5.2f} {r[5]:>8.0f}")

    if args.command == "write":
        args.out.write_text(json.dumps(table, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {args.out} ({len(table)} species)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
