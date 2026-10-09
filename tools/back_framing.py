#!/usr/bin/env python3
"""
Reads each species' back sprite from a pokeemerald-expansion checkout (the cart-style 64x64
sprites) and records where its body sits on screen, so the back pics here can be framed the
same way: close to the player, the lower body behind the battle text box.

The reference does not say how much of the body is cut; it is a 64x64 picture of what shows.
What it does give is (t) the row its body starts on and (v) how many rows tall the body is
there. Our back sprite is placed with its body top on row t and drawn at the clean scale
(1x, 1.5x or 2x, never below 1x) that brings its body height closest to v. Whatever then runs
past the 64 px box is the part the battle GUI hides: that is how much of the top is shown.
The body is measured on the first frame of the (trimmed) animation, so a head or a wing flung
out later (Blacephalon) is not what the Pokemon is sized on.

  python tools/back_framing.py report              # distribution and spot checks
  python tools/back_framing.py write               # write tools/back_framing.json
  python tools/back_framing.py report --only TREECKO TYRANITAR WAILORD

The reference sheet for a species is, in order: <id>/back_gba.png (the cart's own, Gen 1-3),
<id>/back.png, <base>/<form>/back.png, then its base species' sprite. tools/build_atlas.py reads
back_framing.json and stores the row and the scale in each back cell.
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
GEN3_LAST_DEX = ba.GEN3_LAST_DEX


def content_rows(path: Path) -> tuple[int, int, float] | None:
    """(first row, rows tall, centre column) of the picture's content: palette index 0 is transparent in the
    expansion's sprites; a picture with real transparency is read by its alpha."""
    with Image.open(path) as im:
        if im.mode == "P":
            px = im.load()
            test = lambda x, y: px[x, y] != 0  # noqa: E731
        else:
            rgba = im.convert("RGBA")
            px = rgba.load()
            test = lambda x, y: px[x, y][3] > 0  # noqa: E731
        w, h = im.size
        top = bottom = None
        left, right = w, -1
        for y in range(h):
            cols = [x for x in range(w) if test(x, y)]
            if cols:
                if top is None:
                    top = y
                bottom = y
                left, right = min(left, cols[0]), max(right, cols[-1])
    return None if top is None else (top, bottom - top + 1, (left + right + 1) / 2)


def reference_for(ref: Path, sid: str, dex: int) -> Path | None:
    """The reference picture for a species id (see the module doc for the order tried)."""
    name = sid.lower()
    names = [name]
    parts = name.split("_")
    for k in range(len(parts) - 1, 0, -1):          # WORMADAM_SANDY -> wormadam/sandy, then wormadam
        names.append("/".join(("_".join(parts[:k]), "_".join(parts[k:]))))
    names.append("_".join(parts[:1]))
    bases = [name] + [n.split("/")[0] for n in names[1:]]
    seen: set[str] = set()
    for n in names + bases:
        if n in seen:
            continue
        seen.add(n)
        files = ["back_gba.png", "back.png"] if (dex <= GEN3_LAST_DEX and "/" not in n) else ["back.png"]
        for f in files:
            p = ref / n / f
            if p.is_file():
                return p
    return None


def first_frame_height(sheet: Path, window: tuple[int, int] | None) -> int | None:
    """Height of our body on the first frame of the kept animation (the creature's box)."""
    with Image.open(sheet) as im:
        fs = im.height
        start = window[0] if window else 0
        frame = im.convert("RGBA").crop((start * fs, 0, (start + 1) * fs, fs))
    box = frame.getbbox()
    return None if box is None else box[3] - box[1]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=("report", "write"))
    ba.add_source_args(ap)
    ap.add_argument("--ref", type=Path, default=ROOT.parent / "pokeemerald-expansion" / "graphics" / "pokemon",
                    help="the expansion's graphics/pokemon folder")
    ap.add_argument("--trims", type=Path, default=ROOT / "tools" / "loop_trims.json")
    ap.add_argument("--only", nargs="*", help="only these species ids")
    ap.add_argument("--out", type=Path, default=ROOT / "tools" / "back_framing.json")
    args = ap.parse_args()

    trims = json.loads(args.trims.read_text(encoding="utf-8")) if args.trims.exists() else {}
    dbk, species = ba.battle_species(args)
    table: dict[str, dict] = {}
    rows = []
    missing = []
    for dex, sid in species:
        stem = dbk.get(sid)
        if stem is None or (args.only and sid not in args.only):
            continue
        sheet = args.sheets / "back" / f"{stem}.png"
        if not sheet.exists():
            continue
        refpath = reference_for(args.ref, sid, dex)
        if refpath is None:
            missing.append(sid)
            continue
        rc = content_rows(refpath)
        if rc is None:
            missing.append(sid)
            continue
        top, visible, centre = rc
        win = trims.get(sid, {}).get("back")
        h = first_frame_height(sheet, tuple(win) if win else None)
        if not h:
            continue
        scale = ba.back_scale(visible, h)
        table[sid] = {"t": top, "v": visible, "x": centre, "src": refpath.relative_to(args.ref).as_posix()}
        hidden = max(0, top + round(h * scale) - 64)
        rows.append((sid, top, visible, h, scale, hidden))

    print(f"{len(rows)} species framed from {args.ref}")
    if missing:
        print(f"{len(missing)} with no reference (drawn as before): {', '.join(missing[:20])}"
              + (" ..." if len(missing) > 20 else ""))
    by_scale: dict[float, int] = {}
    for r in rows:
        by_scale[r[4]] = by_scale.get(r[4], 0) + 1
    print("scale  " + "   ".join(f"{s:g}x: {n}" for s, n in sorted(by_scale.items())))
    if rows:
        hid = [r[5] / (r[3] * r[4]) for r in rows]
        print(f"share of the body hidden below the box: median {statistics.median(hid):.0%}, "
              f"p90 {sorted(hid)[int(0.9 * len(hid))]:.0%}, max {max(hid):.0%}")
        print("\n  species                      ref top  ref rows  our body  scale  hidden rows")
        spot = ("TREECKO", "PIKACHU", "TYRANITAR", "WAILORD", "BLACEPHALON", "NOIVERN", "ABOMASNOW", "FLOATZEL")
        for r in rows:
            if args.only or r[0] in spot:
                print(f"  {r[0]:<28} {r[1]:>7} {r[2]:>9} {r[3]:>9} {r[4]:>6g} {r[5]:>11}")

    if args.command == "write":
        args.out.write_text(json.dumps(table, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {args.out} ({len(table)} species)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
