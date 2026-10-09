#!/usr/bin/env python3
"""
Finds the enemy front sprites whose feet land below the platform centre and writes how far
to raise each one: data/front_anchor.lua (used with gen3-hd-sprites; sprite_scale.lua's
front_dy overrides it per species).

Where a front pic's feet land on screen (game pixels from the top), singles:
    feet = 72 + FRONT_OFFSET[slot] - ELEVATION[slot] - gap
72 is the enemy pic box's bottom (the spot is (176, 40), the box is 64 tall centred on it);
FRONT_OFFSET / ELEVATION are the engine's per-species tables (pret gMonFrontPicCoords and
gEnemyMonElevation, src/core/game3/battle/pic_coords.lua), which were tuned for the game's own
art and apply to any art drawn for a Gen 1-3 slot; Gen 4-9 slots have none. `gap` is how many
empty rows our art leaves below the creature on the first frame of the kept animation.

Anything whose feet are lower than --line (default 66, the platform's centre) is raised to it;
higher ones (flyers, floaters) are left alone.

  python tools/front_anchor.py report
  python tools/front_anchor.py write
  python tools/front_anchor.py report --only HORSEA GEODUDE
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_atlas as ba  # noqa: E402

ROOT = ba.ROOT
BOX_BOTTOM = 72


def read_pic_coords(path: Path) -> tuple[dict[int, int], dict[int, int]]:
    """(front offsets, elevations) per internal species id from the engine's pic_coords.lua."""
    lines = path.read_text(encoding="utf-8").split("\n")
    marks = {}
    for i, line in enumerate(lines):
        m = re.match(r"^  (front|back|elev) = \{", line)
        if m and m.group(1) not in marks:
            marks[m.group(1)] = i
    order = sorted(marks.items(), key=lambda kv: kv[1])
    spans = {name: (start, order[k + 1][1] if k + 1 < len(order) else len(lines))
             for k, (name, start) in enumerate(order)}

    def table(name):
        out = {}
        a, b = spans[name]
        for line in lines[a:b]:
            m = re.match(r"\s*\[(\d+)\]\s*=\s*(-?\d+)", line)
            if m:
                out[int(m.group(1))] = int(m.group(2))
        return out

    return table("front"), table("elev")


def index_slots(path: Path) -> dict[str, int]:
    """species id -> engine slot, from the generated atlas index."""
    out = {}
    for line in path.read_text(encoding="utf-8").split("\n"):
        m = re.match(r'\s+\["(\w+)"\] = \{ dex = \d+, slot = (\d+),', line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=("report", "write"))
    ba.add_source_args(ap)
    ap.add_argument("--pic-coords", type=Path, default=ROOT.parent / "gen1recomp" / "src" / "core" / "game3"
                    / "battle" / "pic_coords.lua")
    ap.add_argument("--index", type=Path, default=ROOT / "data" / "atlas_index.lua")
    ap.add_argument("--trims", type=Path, default=ROOT / "tools" / "loop_trims.json")
    ap.add_argument("--line", type=int, default=66, help="the feet line, px from the top (default 66)")
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--out", type=Path, default=ROOT / "data" / "front_anchor.lua")
    args = ap.parse_args()

    front, elev = read_pic_coords(args.pic_coords)
    slots = index_slots(args.index)
    trims = json.loads(args.trims.read_text(encoding="utf-8")) if args.trims.exists() else {}
    dbk, species = ba.battle_species(args)
    moves: dict[str, int] = {}
    rows = []
    for _dex, sid in species:
        stem, slot = dbk.get(sid), slots.get(sid)
        if stem is None or slot is None or (args.only and sid not in args.only):
            continue
        sheet = args.sheets / "front" / f"{stem}.png"
        if not sheet.exists():
            continue
        with Image.open(sheet) as im:
            fs = im.height
            win = trims.get(sid, {}).get("front")
            start = win[0] if win else 0
            box = im.convert("RGBA").crop((start * fs, 0, (start + 1) * fs, fs)).getbbox()
        if box is None:
            continue
        gap = fs - box[3]
        feet = BOX_BOTTOM + front.get(slot, 0) - elev.get(slot, 0) - gap + ba.FRONT_DROP.get(sid, 0)
        dy = args.line - feet if feet > args.line else 0
        rows.append((sid, slot, front.get(slot, 0), elev.get(slot, 0), gap, feet, dy))
        if dy:
            moves[sid] = dy

    low = [r for r in rows if r[6]]
    print(f"{len(rows)} front sprites; {len(low)} land below y={args.line} and are raised "
          f"(median raise {sorted(r[6] for r in low)[len(low) // 2] if low else 0} px)")
    print("\n  species                   slot  y_off  elev  gap  feet y  raise")
    shown = [r for r in rows if (args.only and r[0] in args.only)] or sorted(low, key=lambda r: r[6])[:14]
    for r in shown:
        print(f"  {r[0]:<24} {r[1]:>5} {r[2]:>6} {r[3]:>5} {r[4]:>4} {r[5]:>7} {r[6]:>6}")

    if args.command == "write":
        lines = [
            "-- Generated by tools/front_anchor.py. Do not edit by hand; edit data/sprite_scale.lua instead",
            f"-- (front_dy there overrides this). How far each enemy front sprite is raised (negative =",
            f"-- up, game px) so its feet are no lower than y = {args.line}, the platform's centre.",
            "return {",
        ]
        for sid in sorted(moves):
            lines.append(f"  {sid} = {moves[sid]},")
        lines += ["}", ""]
        args.out.write_text("\n".join(lines), encoding="utf-8")
        print(f"\nwrote {args.out} ({len(moves)} species)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
