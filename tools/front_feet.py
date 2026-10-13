#!/usr/bin/env python3
"""
Checks where the enemy front sprites stand, by their RESTING pose (tools/front_pose.py: the frames
most alike, the pose the animation keeps coming back to, at their median bottom):

  * floating: grounded species whose feet rest above the platform centre (--line, y 66) - Litten
  * sunk:     species whose feet rest below it
  * --dips:   sprites with more than --max-dips frames whose bottom goes below the top of the
              player's health box (--ui-line, y 72): a hop or a bob is fine, more is an outlier to
              look at (a bad anchor, or a species to tune in data/sprite_scale.lua)
  * --tops:   sprites whose BODY (the middle third of their columns, not wings or arms) goes above
              the window's top in more than --max-tops frames

Flyers and floaters are left out of floating/sunk: Wilds of Hoenn's `fly` list (lib/pmd_water.lua,
the species with no PMD swim look) and AIRBORNE below.

Where a frame row lands (game px from the top, singles):
    base = 72 + FRONT_OFFSET[slot] - ELEVATION[slot] + fy   (fy: the cell's drop + raise + nudge)
    plain (no gen3-hd-sprites): y = base - (fs - row)
    HD: y = base + dy - (fs - row) * k   (dy, k: front_dy and front in sprite_scale.lua)

  python tools/front_feet.py                    # floating and sunk
  python tools/front_feet.py --dips             # the dip outliers
  python tools/front_feet.py --tops             # the out-of-the-top outliers
  python tools/front_feet.py --only LITTEN HORSEA
  python tools/front_feet.py --write            # tools/front_drop.json: lower the floaters

--write lowers every grounded species floating --fix-from px or more (default 8) so its resting
feet stand on the line, except flyers and AIRBORNE. tools/build_atlas.py reads front_drop.json into
the front cells' drop (`fy`), so it applies with and without gen3-hd-sprites; then rebuild the atlas
and rerun tools/front_anchor.py write.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_atlas as ba  # noqa: E402
import front_anchor as fa  # noqa: E402
import front_pose as fp  # noqa: E402

ROOT = ba.ROOT
BOX_BOTTOM = fa.BOX_BOTTOM

# Drawn in the air on purpose, though Wilds of Hoenn's list (water only) does not say so: never
# lowered by --write. Edit by hand.
AIRBORNE = {
    "COSMOG", "LUGIA", "MOLTRES", "MINIOR", "CARBINK", "SPRITZEE", "FLITTLE", "DOTTLER", "INKAY",
    "IRON_BUNDLE", "DOUBLADE", "COFAGRIGUS", "BRAMBLEGHAST", "GHOLDENGO", "THUNDURUS_THERIAN",
    "WATTREL", "KILOWATTREL", "SQUAWKABILLY", "ORICORIO", "TRUMBEAK", "EMOLGA",
    "FLABEBE", "FLABEBE_YELLOW", "FLABEBE_ORANGE", "FLABEBE_BLUE", "FLABEBE_WHITE",
    "ARTICUNO_GALAR",
}


def read_flyers(path: Path) -> tuple[set[int], dict[str, bool]]:
    """Wilds of Hoenn's `fly` list: dex numbers, and form keys ("479-heat") -> on/off."""
    dexes: set[int] = set()
    forms: dict[str, bool] = {}
    if not path.exists():
        return dexes, forms
    text = path.read_text(encoding="utf-8")
    m = re.search(r"\bfly\s*=\s*\{(.*?)\n  \}", text, re.S)
    body = m.group(1) if m else text
    for k, v in re.findall(r"\[(\d+)\]\s*=\s*(true|false)", body):
        if v == "true":
            dexes.add(int(k))
    for k, v in re.findall(r'\["(\d+-[\w-]+)"\]\s*=\s*(true|false)', body):
        forms[k] = v == "true"
    return dexes, forms


def is_flyer(dex: int, sid: str, dexes: set[int], forms: dict[str, bool]) -> bool:
    parts = sid.lower().split("_", 1)
    if len(parts) == 2:
        key = f"{dex:03d}-{parts[1].replace('_', '-')}"
        if key in forms:
            return forms[key]
    return dex in dexes


def read_tuning(path: Path) -> tuple[dict[str, dict[str, float]], float]:
    """data/sprite_scale.lua: per-species { front = k, front_dy = px, ... } and all.front."""
    out: dict[str, dict[str, float]] = {}
    mul = 1.0
    if not path.exists():
        return out, mul
    for name, body in re.findall(r"^\s*([A-Za-z_][\w]*)\s*=\s*\{([^}]*)\}", path.read_text(encoding="utf-8"), re.M):
        vals = {k: float(v) for k, v in re.findall(r"(\w+)\s*=\s*(-?[\d.]+)", body)}
        if name == "all":
            mul = vals.get("front", 1.0)
        else:
            out[name] = vals
    return out, mul


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ba.add_source_args(ap)
    ap.add_argument("--pic-coords", type=Path, default=ROOT.parent / "gen1recomp" / "src" / "core" / "game3"
                    / "battle" / "pic_coords.lua")
    ap.add_argument("--index", type=Path, default=ROOT / "data" / "atlas_index.lua")
    ap.add_argument("--trims", type=Path, default=ROOT / "tools" / "loop_trims.json")
    ap.add_argument("--flyers", type=Path, default=ROOT.parent / "wilds-of-hoenn" / "lib" / "pmd_water.lua")
    ap.add_argument("--tuning", type=Path, default=ROOT / "data" / "sprite_scale.lua")
    ap.add_argument("--line", type=int, default=66, help="the feet line, px from the top (default 66)")
    ap.add_argument("--tolerance", type=int, default=3, help="px off the line still counted as on it")
    ap.add_argument("--ui-line", type=int, default=72,
                    help="top of the player's health box (centre y 88, 32 tall; default 72)")
    ap.add_argument("--max-dips", type=int, default=4, help="frames allowed below --ui-line")
    ap.add_argument("--max-tops", type=int, default=4, help="frames allowed with the body above y 0")
    ap.add_argument("--dips", action="store_true", help="print the dip outliers only")
    ap.add_argument("--tops", action="store_true", help="print the out-of-the-top outliers only")
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--json", type=Path, help="also write every measured species here")
    ap.add_argument("--write", action="store_true", help="write tools/front_drop.json (see above)")
    ap.add_argument("--fix-from", type=int, default=8, help="--write lowers species this far up or more")
    ap.add_argument("--out", type=Path, default=ROOT / "tools" / "front_drop.json")
    args = ap.parse_args()

    front, elev = fa.read_pic_coords(args.pic_coords)
    slots = fa.index_slots(args.index)
    trims = json.loads(args.trims.read_text(encoding="utf-8")) if args.trims.exists() else {}
    dexes, forms = read_flyers(args.flyers)
    tuning, mul = read_tuning(args.tuning)
    dbk, species = ba.battle_species(args)
    # --write measures from the hand-set drops only, so a rerun does not stack on the last one
    drops = ba.FRONT_DROP_MANUAL if args.write else ba.FRONT_DROP
    rows, seen = [], set()
    for dex, sid in species:
        stem, slot = dbk.get(sid), slots.get(sid)
        if sid in seen or stem is None or slot is None or (args.only and sid not in args.only):
            continue
        seen.add(sid)
        sheet = args.sheets / "front" / f"{stem}.png"
        if not sheet.exists():
            continue
        rest = fp.rest_gap(sheet, trims.get(sid, {}).get("front"))
        if rest is None:
            continue
        gap, fs, frames = rest
        # what the atlas puts in the cell (--write: the hand-set drops only, so a rerun does not
        # stack on the last one's drop, raise or nudge)
        fy = drops.get(sid, 0) if args.write else ba.front_fy(sid)
        base = BOX_BOTTOM + front.get(slot, 0) - elev.get(slot, 0) + fy
        feet = base - gap
        own = tuning.get(sid, {})
        dy = int(own.get("front_dy", 0))
        k = own.get("front", 1.0) * mul

        def plain_y(row: int) -> float:
            return base - (fs - row)

        def hd_y(row: int) -> float:
            return base + dy - (fs - row) * k

        bottoms = [b for b in fp.frame_bottoms(frames) if b is not None]
        tops = [t for t in fp.centre_tops(frames) if t is not None]
        n = len(bottoms)
        dips = {m: [y - args.ui_line for y in map(f, bottoms) if y > args.ui_line]
                for m, f in (("plain", plain_y), ("hd", hd_y))}
        outs = {m: [-y for y in map(f, tops) if y < 0] for m, f in (("plain", plain_y), ("hd", hd_y))}
        rows.append({
            "sid": sid, "dex": dex, "slot": slot, "gen13": slot < 451,
            "flyer": is_flyer(dex, sid, dexes, forms) or sid in AIRBORNE,
            "offset": front.get(slot, 0), "elev": elev.get(slot, 0), "fy": fy,
            # feet / above: with gen3-hd-sprites (front_dy and the per-species
            # size are gen3-hd-sprites only); plain_feet: without that library
            "frames": n, "gap": gap, "feet": round(base + dy - gap * k, 1),
            "above": round(args.line - (base + dy - gap * k), 1), "plain_feet": feet,
            "raw_above": args.line - feet,
            "low": (max(bottoms) - (fs - gap)) if bottoms else 0,
            "dips": {m: {"frames": len(v), "deepest": round(max(v), 1) if v else 0} for m, v in dips.items()},
            "tops": {m: {"frames": len(v), "worst": round(max(v), 1) if v else 0} for m, v in outs.items()},
        })

    def show(title: str, items: list[dict], extra) -> None:
        print(f"\n{title}")
        if not items:
            print("  (none)")
        for r in items:
            print(f"  {r['sid']:<26} {r['dex']:>4}  " + extra(r))

    print(f"{len(rows)} front sprites measured by their resting pose; platform line y={args.line}, "
          f"health box top y={args.ui_line}")
    if args.only:
        show("species                     dex  feet y at rest / above line / lowest frame lower by / "
             "dip frames plain, HD / top frames plain, HD", rows,
             lambda r: f"{r['feet']:>4} {r['above']:>4} {r['low']:>4}   "
             f"{r['dips']['plain']['frames']:>3} {r['dips']['hd']['frames']:>3}   "
             f"{r['tops']['plain']['frames']:>3} {r['tops']['hd']['frames']:>3}  of {r['frames']}"
             + ("  (flyer/floater)" if r["flyer"] else ""))
        return 0

    dip_out = sorted((r for r in rows if max(r["dips"]["plain"]["frames"], r["dips"]["hd"]["frames"]) > args.max_dips),
                     key=lambda r: -max(r["dips"]["plain"]["frames"], r["dips"]["hd"]["frames"]))
    top_out = sorted((r for r in rows if max(r["tops"]["plain"]["frames"], r["tops"]["hd"]["frames"]) > args.max_tops),
                     key=lambda r: -max(r["tops"]["plain"]["frames"], r["tops"]["hd"]["frames"]))

    def dip_text(r):
        p, h = r["dips"]["plain"], r["dips"]["hd"]
        return (f"plain {p['frames']:>2}/{r['frames']} frames, {p['deepest']:>4} px deep | "
                f"HD {h['frames']:>2}/{r['frames']}, {h['deepest']:>4} px")

    def top_text(r):
        p, h = r["tops"]["plain"], r["tops"]["hd"]
        only = "  (plain only: HD sizing keeps it in)" if p["frames"] > args.max_tops >= h["frames"] else ""
        return (f"plain {p['frames']:>2}/{r['frames']} frames, {p['worst']:>4} px out | "
                f"HD {h['frames']:>2}/{r['frames']}, {h['worst']:>4} px" + only)

    if args.dips or args.tops:
        if args.dips:
            show(f"{len(dip_out)} dip below the health box (y {args.ui_line}) in more than {args.max_dips} frames",
                 dip_out, dip_text)
        if args.tops:
            show(f"{len(top_out)} have their body above the window in more than {args.max_tops} frames",
                 top_out, top_text)
    else:
        grounded = [r for r in rows if not r["flyer"]]
        floating = sorted((r for r in grounded if r["above"] > args.tolerance), key=lambda r: -r["above"])
        sunk = sorted((r for r in grounded if -r["above"] > args.tolerance), key=lambda r: r["above"])
        print(f"{len(rows) - len(grounded)} flyers / floaters left out ({args.flyers.name} + AIRBORNE)")
        print(f"{len(floating)} grounded rest more than {args.tolerance} px ABOVE the line, "
              f"{len(sunk)} more than {args.tolerance} px BELOW it; "
              f"{len(dip_out)} dip outliers (--dips), {len(top_out)} out-of-the-top outliers (--tops)")

        def both(r):
            return (f"rests {r['above']:>5} px above the line (feet y {r['feet']}; without HD y {r['plain_feet']}), "
                    f"lowest frame {r['low']} px lower")
        show("floating", floating, both)
        show("sunk", sunk, both)

    if args.json:
        args.json.write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
        print(f"\nwrote {args.json}")
    if args.write:
        fix = {r["sid"]: r["raw_above"] for r in rows
               if r["raw_above"] >= args.fix_from and not r["flyer"] and r["sid"] not in ba.FRONT_DROP_MANUAL}
        kept = sorted(r["sid"] for r in rows if r["raw_above"] >= args.fix_from and r["sid"] in AIRBORNE)
        args.out.write_text(json.dumps(fix, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {args.out}: {len(fix)} species lowered onto y={args.line}; "
              f"left in the air (AIRBORNE): {', '.join(kept)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
